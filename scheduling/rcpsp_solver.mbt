///|
/// Deterministic priority rules over the same RCPSP problem.
pub(all) enum RcpspAlgorithm {
  StableTopological
  CriticalPath
  RecoveryHeuristic
}

///|
/// A heuristic result is FEASIBLE or UNKNOWN; it never proves infeasibility.
pub(all) struct RcpspSolveResult {
  status : String
  algorithm : String
  schedule : Array[RcpspScheduleEntry]
  makespan : Int?
  candidates_evaluated : Int
  accepted_moves : Int
  budget : Int
  elapsed_ms : UInt64
  diagnostic : String?
}

///|
fn rcpsp_algorithm_name(algorithm : RcpspAlgorithm) -> String {
  match algorithm {
    StableTopological => "stable-topological"
    CriticalPath => "critical-path"
    RecoveryHeuristic => "recovery-heuristic"
  }
}

///|
fn rcpsp_path_lengths(
  problem : RcpspProblem,
) -> Array[Int] raise SchedulingError {
  let remaining : Array[Int] = []
  for task in problem.tasks {
    remaining.push(task.duration)
  }
  for _ in problem.tasks {
    for edge in problem.dependencies {
      let before = match rcpsp_task_index(problem.tasks, edge.prerequisite_id) {
        Some(value) => value
        None => abort("validated prerequisite disappeared")
      }
      let after = match rcpsp_task_index(problem.tasks, edge.task_id) {
        Some(value) => value
        None => abort("validated dependent disappeared")
      }
      let path = checked_finish(
        problem.tasks[before].duration,
        remaining[after],
      )
      if path > remaining[before] {
        remaining[before] = path
      }
    }
  }
  remaining
}

///|
fn rcpsp_ready(
  problem : RcpspProblem,
  index : Int,
  selected : Array[Bool],
) -> Bool {
  for edge in problem.dependencies {
    if edge.task_id == problem.tasks[index].id {
      let before = match rcpsp_task_index(problem.tasks, edge.prerequisite_id) {
        Some(value) => value
        None => abort("validated prerequisite disappeared")
      }
      if !selected[before] {
        return false
      }
    }
  }
  true
}

///|
fn rcpsp_order(
  problem : RcpspProblem,
  algorithm : RcpspAlgorithm,
) -> Array[Int] raise SchedulingError {
  let paths = rcpsp_path_lengths(problem)
  let selected : Array[Bool] = []
  for _ in problem.tasks {
    selected.push(false)
  }
  let order : Array[Int] = []
  for _ in problem.tasks {
    let mut chosen : Int? = None
    for i, task in problem.tasks {
      if !selected[i] && rcpsp_ready(problem, i, selected) {
        match chosen {
          None => chosen = Some(i)
          Some(current) => {
            let better = match algorithm {
              StableTopological => false
              CriticalPath => paths[i] > paths[current]
              RecoveryHeuristic =>
                task.priority > problem.tasks[current].priority ||
                (
                  task.priority == problem.tasks[current].priority &&
                  paths[i] > paths[current]
                )
            }
            if better {
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
/// Capacity can change only at an already booked start or finish. A new
/// earliest feasible start is therefore the release/precedence time or an
/// existing finish event; no unit-by-unit time scan is needed.
fn rcpsp_slot_fits(
  problem : RcpspProblem,
  task : RcpspTask,
  start : Int,
  booked : Array[RcpspScheduleEntry],
) -> Bool {
  if task.duration > 2147483647 - start {
    return false
  }
  let finish = start + task.duration
  for demand in task.demands {
    let resource_index = match
      rcpsp_resource_index(problem.resources, demand.resource_id) {
      Some(value) => value
      None => abort("validated resource disappeared")
    }
    let capacity = problem.resources[resource_index].capacity
    for probe in 0..<=booked.length() {
      let time = if probe == booked.length() {
        start
      } else {
        booked[probe].start
      }
      if time >= start && time < finish {
        let mut used = demand.amount
        for entry in booked {
          if entry.start <= time && time < entry.finish {
            let index = match rcpsp_task_index(problem.tasks, entry.task_id) {
              Some(value) => value
              None => abort("booked task disappeared")
            }
            let amount = demand_for(problem.tasks[index], demand.resource_id)
            if amount > capacity - used {
              return false
            }
            used = used + amount
          }
        }
      }
    }
  }
  true
}

///|
fn rcpsp_earliest_slot(
  problem : RcpspProblem,
  task : RcpspTask,
  earliest : Int,
  booked : Array[RcpspScheduleEntry],
) -> Int? {
  let mut best : Int? = None
  if rcpsp_slot_fits(problem, task, earliest, booked) {
    best = Some(earliest)
  }
  for entry in booked {
    if entry.finish >= earliest &&
      rcpsp_slot_fits(problem, task, entry.finish, booked) {
      match best {
        None => best = Some(entry.finish)
        Some(value) => if entry.finish < value { best = Some(entry.finish) }
      }
    }
  }
  best
}

///|
fn rcpsp_decode(
  problem : RcpspProblem,
  order : Array[Int],
) -> Array[RcpspScheduleEntry]? {
  let completion : Array[Int] = []
  for _ in problem.tasks {
    completion.push(0)
  }
  let schedule : Array[RcpspScheduleEntry] = []
  for index in order {
    let task = problem.tasks[index]
    let mut earliest = task.release_time
    for edge in problem.dependencies {
      if edge.task_id == task.id {
        let before = match
          rcpsp_task_index(problem.tasks, edge.prerequisite_id) {
          Some(value) => value
          None => abort("validated prerequisite disappeared")
        }
        if completion[before] > earliest {
          earliest = completion[before]
        }
      }
    }
    let start = match rcpsp_earliest_slot(problem, task, earliest, schedule) {
      Some(value) => value
      None => return None
    }
    let finish = start + task.duration
    schedule.push({ task_id: task.id, start, finish, })
    completion[index] = finish
  }
  Some(schedule)
}

///|
fn rcpsp_makespan(schedule : Array[RcpspScheduleEntry]) -> Int {
  let mut finish = 0
  for entry in schedule {
    if entry.finish > finish {
      finish = entry.finish
    }
  }
  finish
}

///|
fn rcpsp_valid_candidate(
  problem : RcpspProblem,
  order : Array[Int],
) -> Array[RcpspScheduleEntry]? {
  match rcpsp_decode(problem, order) {
    None => None
    Some(schedule) =>
      if inspect_rcpsp_schedule(problem, schedule).is_empty() {
        Some(schedule)
      } else {
        None
      }
  }
}

///|
fn rcpsp_result(
  algorithm : String,
  schedule : Array[RcpspScheduleEntry]?,
  candidates_evaluated : Int,
  accepted_moves : Int,
  budget : Int,
  started : UInt64,
) -> RcpspSolveResult {
  match schedule {
    Some(value) =>
      {
        status: "FEASIBLE",
        algorithm,
        schedule: value,
        makespan: Some(rcpsp_makespan(value)),
        candidates_evaluated,
        accepted_moves,
        budget,
        elapsed_ms: @env.now() - started,
        diagnostic: None,
      }
    None =>
      {
        status: "UNKNOWN",
        algorithm,
        schedule: [],
        makespan: None,
        candidates_evaluated,
        accepted_moves,
        budget,
        elapsed_ms: @env.now() - started,
        diagnostic: Some("no feasible schedule found within heuristic search"),
      }
  }
}

///|
pub fn solve_rcpsp(
  problem : RcpspProblem,
  algorithm : RcpspAlgorithm,
) -> RcpspSolveResult raise SchedulingError {
  let started = @env.now()
  validate_rcpsp_problem(problem)
  let order = rcpsp_order(problem, algorithm)
  rcpsp_result(
    rcpsp_algorithm_name(algorithm),
    rcpsp_valid_candidate(problem, order),
    1,
    0,
    0,
    started,
  )
}

///|
fn rcpsp_order_feasible(problem : RcpspProblem, order : Array[Int]) -> Bool {
  let positions : Array[Int] = []
  for _ in problem.tasks {
    positions.push(-1)
  }
  for i, index in order {
    positions[index] = i
  }
  for edge in problem.dependencies {
    let before = match rcpsp_task_index(problem.tasks, edge.prerequisite_id) {
      Some(value) => value
      None => abort("validated prerequisite disappeared")
    }
    let after = match rcpsp_task_index(problem.tasks, edge.task_id) {
      Some(value) => value
      None => abort("validated dependent disappeared")
    }
    if positions[before] >= positions[after] {
      return false
    }
  }
  true
}

///|
/// Budget counts evaluated feasible activity-list neighbours. Every decoded
/// candidate is checked by the independent validator before comparison.
pub fn optimize_rcpsp(
  problem : RcpspProblem,
  budget : Int,
) -> RcpspSolveResult raise SchedulingError {
  let started = @env.now()
  validate_rcpsp_problem(problem)
  if budget < 0 {
    raise SchedulingError::InvalidConstraint("search budget cannot be negative")
  }
  let mut best : Array[RcpspScheduleEntry]? = None
  let mut best_order : Array[Int] = []
  let mut evaluations = 0
  for
    algorithm in [
      RcpspAlgorithm::StableTopological,
      RcpspAlgorithm::CriticalPath,
      RcpspAlgorithm::RecoveryHeuristic,
    ] {
    let order = rcpsp_order(problem, algorithm)
    evaluations = evaluations + 1
    match rcpsp_valid_candidate(problem, order) {
      Some(candidate) =>
        match best {
          None => {
            best = Some(candidate)
            best_order = order
          }
          Some(current) =>
            if rcpsp_makespan(candidate) < rcpsp_makespan(current) {
              best = Some(candidate)
              best_order = order
            }
        }
      None => ()
    }
  }
  let mut moves = 0
  let mut searched = 0
  let mut scanning = true
  while scanning && searched < budget && !best_order.is_empty() {
    scanning = false
    for position in 0..<(best_order.length() - 1) {
      if searched >= budget {
        break
      }
      let proposal = best_order.copy()
      proposal[position] = best_order[position + 1]
      proposal[position + 1] = best_order[position]
      if rcpsp_order_feasible(problem, proposal) {
        searched = searched + 1
        evaluations = evaluations + 1
        match rcpsp_valid_candidate(problem, proposal) {
          Some(candidate) =>
            match best {
              Some(current) =>
                if rcpsp_makespan(candidate) < rcpsp_makespan(current) {
                  best = Some(candidate)
                  best_order = proposal
                  moves = moves + 1
                  scanning = true
                  break
                }
              None => ()
            }
          None => ()
        }
      }
    }
  }
  rcpsp_result(
    "budgeted-local-search", best, evaluations, moves, budget, started,
  )
}
