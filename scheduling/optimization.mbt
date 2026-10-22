///|
/// Measured outcome of a deterministic, budgeted local search.
pub(all) struct OptimizationReport {
  best_baseline_makespan : Int
  initial_makespan : Int
  lower_bound : Int
  result : AnalysisResult
  candidates_evaluated : Int
  accepted_moves : Int
  budget : Int
}

///|
fn relaxed_problem(problem : SchedulingProblem) -> SchedulingProblem {
  {
    tasks: problem.tasks,
    dependencies: problem.dependencies,
    constraints: {
      resources: problem.constraints.resources,
      target_makespan: None,
    },
  }
}

///|
fn resource_loads(
  problem : SchedulingProblem,
) -> Array[Int] raise SchedulingError {
  let loads : Array[Int] = []
  for resource in problem.constraints.resources {
    let mut load = 0
    for task in problem.tasks {
      if task.resource_id == resource.id {
        load = checked_finish(load, task.duration)
      }
    }
    loads.push(load)
  }
  loads
}

///|
fn load_for_task(
  task : Task,
  resources : Array[Resource],
  loads : Array[Int],
) -> Int {
  for i, resource in resources {
    if resource.id == task.resource_id {
      return loads[i]
    }
  }
  abort("validated resource disappeared")
}

///|
fn adaptive_order(
  problem : SchedulingProblem,
  remaining : Array[Int],
  loads : Array[Int],
  critical_path_priority : Bool,
  resource_load_awareness : Bool,
) -> Array[Int] {
  let selected : Array[Bool] = []
  for _ in problem.tasks {
    selected.push(false)
  }
  let order : Array[Int] = []
  for _ in problem.tasks {
    let mut chosen : Int? = None
    for i, task in problem.tasks {
      if !selected[i] && prerequisites_selected(problem, i, selected) {
        match chosen {
          None => chosen = Some(i)
          Some(current) => {
            let contender_load = load_for_task(
              task,
              problem.constraints.resources,
              loads,
            )
            let current_load = load_for_task(
              problem.tasks[current],
              problem.constraints.resources,
              loads,
            )
            let contender_path = if critical_path_priority {
              remaining[i]
            } else {
              0
            }
            let current_path = if critical_path_priority {
              remaining[current]
            } else {
              0
            }
            let contender_load = if resource_load_awareness {
              contender_load
            } else {
              0
            }
            let current_load = if resource_load_awareness {
              current_load
            } else {
              0
            }
            if contender_path > current_path ||
              (contender_path == current_path && contender_load > current_load) ||
              (
                contender_path == current_path &&
                contender_load == current_load &&
                task.priority > problem.tasks[current].priority
              ) {
              chosen = Some(i)
            }
          }
        }
      }
    }
    let index = match chosen {
      Some(value) => value
      None => abort("validated DAG has no ready task")
    }
    selected[index] = true
    order.push(index)
  }
  order
}

///|
fn order_from_schedule(
  problem : SchedulingProblem,
  schedule : Array[ScheduleEntry],
) -> Array[Int] {
  let order : Array[Int] = []
  for entry in schedule {
    let index = match task_index(problem.tasks, entry.task_id) {
      Some(value) => value
      None => abort("validated schedule task disappeared")
    }
    order.push(index)
  }
  order
}

///|
fn precedence_feasible_order(
  problem : SchedulingProblem,
  order : Array[Int],
) -> Bool {
  let position : Array[Int] = []
  for _ in problem.tasks {
    position.push(-1)
  }
  for place, index in order {
    position[index] = place
  }
  for edge in problem.dependencies {
    let dependent = match task_index(problem.tasks, edge.task_id) {
      Some(value) => value
      None => abort("validated dependent disappeared")
    }
    let predecessor = match task_index(problem.tasks, edge.prerequisite_id) {
      Some(value) => value
      None => abort("validated predecessor disappeared")
    }
    if position[predecessor] >= position[dependent] {
      return false
    }
  }
  true
}

///|
/// Builds a critical-path/resource-load seed, then tries adjacent swaps of a
/// precedence-feasible activity list. Only strict makespan improvements stick.
/// This is a heuristic, not an optimality proof.
pub fn optimize_schedule(
  problem : SchedulingProblem,
  budget : Int,
) -> OptimizationReport raise SchedulingError {
  optimize_schedule_with_features(problem, budget, true, true, true)
}

///|
/// Experimental switches for a one-factor-at-a-time ablation. The three
/// unchanged baselines remain eligible, so disabling a seed feature never
/// removes the corresponding baseline from the safety fallback.
pub fn optimize_schedule_with_features(
  problem : SchedulingProblem,
  budget : Int,
  critical_path_priority : Bool,
  resource_load_awareness : Bool,
  local_search : Bool,
) -> OptimizationReport raise SchedulingError {
  validate_problem(problem)
  if budget < 0 {
    raise SchedulingError::InvalidConstraint("search budget cannot be negative")
  }
  let relaxed = relaxed_problem(problem)
  let topo = run_baseline(relaxed, StableTopological)
  let recovery = run_baseline(relaxed, RecoveryHeuristic)
  let critical = run_baseline(relaxed, CriticalPath)
  let mut best = topo
  for candidate in [recovery, critical] {
    if candidate.makespan < best.makespan {
      best = candidate
    }
  }
  let best_baseline_makespan = best.makespan
  let order = stable_order(relaxed)
  let (remaining, _) = path_metrics(relaxed, order)
  let loads = resource_loads(relaxed)
  let mut lower_bound = 0
  for path in remaining {
    if path > lower_bound {
      lower_bound = path
    }
  }
  for load in loads {
    if load > lower_bound {
      lower_bound = load
    }
  }
  let adaptive = decode_order(
    relaxed,
    adaptive_order(
      relaxed, remaining, loads, critical_path_priority, resource_load_awareness,
    ),
    "adaptive-critical-path-load",
  )
  if adaptive.makespan < best.makespan {
    best = adaptive
  }
  let initial_makespan = best.makespan
  let mut current_order = order_from_schedule(relaxed, best.schedule)
  let mut candidates_evaluated = 0
  let mut accepted_moves = 0
  let mut searching = true
  while local_search &&
        searching &&
        candidates_evaluated < budget &&
        best.makespan > lower_bound {
    searching = false
    for i in 0..<(current_order.length() - 1) {
      if candidates_evaluated >= budget {
        break
      }
      let candidate_order = current_order.copy()
      let first = candidate_order[i]
      candidate_order[i] = candidate_order[i + 1]
      candidate_order[i + 1] = first
      if precedence_feasible_order(relaxed, candidate_order) {
        candidates_evaluated = candidates_evaluated + 1
        let candidate = decode_order(
          relaxed, candidate_order, "adaptive-local-search",
        )
        if candidate.makespan < best.makespan {
          best = candidate
          current_order = candidate_order
          accepted_moves = accepted_moves + 1
          searching = true
          break
        }
      }
    }
  }
  let algorithm = if accepted_moves > 0 {
    "adaptive-local-search"
  } else {
    best.explanation.algorithm
  }
  let result = evaluate_schedule(problem~, schedule=best.schedule, algorithm~)
  {
    best_baseline_makespan,
    initial_makespan,
    lower_bound,
    result,
    candidates_evaluated,
    accepted_moves,
    budget,
  }
}
