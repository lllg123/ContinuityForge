///|
/// Deterministic list-scheduling policies on the same problem and validator.
pub(all) enum Baseline {
  StableTopological
  RecoveryHeuristic
  CriticalPath
}

///|
fn baseline_name(baseline : Baseline) -> String {
  match baseline {
    StableTopological => "stable-topological"
    RecoveryHeuristic => "recovery-heuristic"
    CriticalPath => "critical-path"
  }
}

///|
fn checked_finish(start : Int, duration : Int) -> Int raise SchedulingError {
  if duration > 2147483647 - start {
    raise SchedulingError::InvalidSchedule(
      "schedule exceeds integer time range",
    )
  }
  start + duration
}

///|
fn stable_order(problem : SchedulingProblem) -> Array[Int] {
  let indegree : Array[Int] = []
  for _ in problem.tasks {
    indegree.push(0)
  }
  for edge in problem.dependencies {
    let dependent = match task_index(problem.tasks, edge.task_id) {
      Some(index) => index
      None => abort("validated dependent disappeared")
    }
    indegree[dependent] = indegree[dependent] + 1
  }
  let ready : Array[Int] = []
  for i, degree in indegree {
    if degree == 0 {
      ready.push(i)
    }
  }
  let mut cursor = 0
  while cursor < ready.length() {
    let finished = problem.tasks[ready[cursor]].id
    cursor = cursor + 1
    for edge in problem.dependencies {
      if edge.prerequisite_id == finished {
        let dependent = match task_index(problem.tasks, edge.task_id) {
          Some(index) => index
          None => abort("validated dependent disappeared")
        }
        indegree[dependent] = indegree[dependent] - 1
        if indegree[dependent] == 0 {
          ready.push(dependent)
        }
      }
    }
  }
  ready
}

///|
fn path_metrics(
  problem : SchedulingProblem,
  order : Array[Int],
) -> (Array[Int], Array[Int]) raise SchedulingError {
  let remaining : Array[Int] = []
  let downstream_priority : Array[Int] = []
  for task in problem.tasks {
    remaining.push(task.duration)
    downstream_priority.push(task.priority)
  }
  for position in 0..<order.length() {
    let index = order[order.length() - 1 - position]
    let task = problem.tasks[index]
    for edge in problem.dependencies {
      if edge.prerequisite_id == task.id {
        let dependent = match task_index(problem.tasks, edge.task_id) {
          Some(value) => value
          None => abort("validated dependent disappeared")
        }
        if downstream_priority[dependent] > downstream_priority[index] {
          downstream_priority[index] = downstream_priority[dependent]
        }
        let path = checked_finish(task.duration, remaining[dependent])
        if path > remaining[index] {
          remaining[index] = path
        }
      }
    }
  }
  (remaining, downstream_priority)
}

///|
fn prerequisites_selected(
  problem : SchedulingProblem,
  index : Int,
  selected : Array[Bool],
) -> Bool {
  for edge in problem.dependencies {
    if edge.task_id == problem.tasks[index].id {
      let prerequisite = match task_index(problem.tasks, edge.prerequisite_id) {
        Some(value) => value
        None => abort("validated prerequisite disappeared")
      }
      if !selected[prerequisite] {
        return false
      }
    }
  }
  true
}

///|
fn better_candidate(
  candidate : Int,
  current : Int,
  problem : SchedulingProblem,
  baseline : Baseline,
  remaining : Array[Int],
  downstream_priority : Array[Int],
) -> Bool {
  let candidate_task = problem.tasks[candidate]
  let current_task = problem.tasks[current]
  match baseline {
    StableTopological => false
    CriticalPath => remaining[candidate] > remaining[current]
    RecoveryHeuristic =>
      if downstream_priority[candidate] != downstream_priority[current] {
        downstream_priority[candidate] > downstream_priority[current]
      } else if remaining[candidate] - candidate_task.duration !=
        remaining[current] - current_task.duration {
        remaining[candidate] - candidate_task.duration >
        remaining[current] - current_task.duration
      } else if candidate_task.priority != current_task.priority {
        candidate_task.priority > current_task.priority
      } else if candidate_task.duration != current_task.duration {
        candidate_task.duration < current_task.duration
      } else {
        candidate_task.id < current_task.id
      }
  }
}

///|
fn earliest_slot(
  task : Task,
  earliest : Int,
  booked : Array[ScheduleEntry],
) -> Int raise SchedulingError {
  let mut start = earliest
  let mut searching = true
  while searching {
    searching = false
    let finish = checked_finish(start, task.duration)
    for entry in booked {
      if entry.resource_id == task.resource_id &&
        start < entry.finish &&
        entry.start < finish {
        start = entry.finish
        searching = true
        break
      }
    }
  }
  start
}

///|
/// Runs one baseline and independently validates the resulting schedule.
/// Priority in RecoveryHeuristic is the caller's domain-neutral integer rank.
pub fn run_baseline(
  problem : SchedulingProblem,
  baseline : Baseline,
) -> AnalysisResult raise SchedulingError {
  validate_problem(problem)
  let order = stable_order(problem)
  let (remaining, downstream_priority) = match baseline {
    StableTopological => ([], [])
    RecoveryHeuristic | CriticalPath => path_metrics(problem, order)
  }
  let selected : Array[Bool] = []
  let completion : Array[Int] = []
  for _ in problem.tasks {
    selected.push(false)
    completion.push(0)
  }
  let schedule : Array[ScheduleEntry] = []
  for position in 0..<problem.tasks.length() {
    let index = match baseline {
      StableTopological => order[position]
      RecoveryHeuristic | CriticalPath => {
        let mut chosen : Int? = None
        for i in 0..<problem.tasks.length() {
          if !selected[i] && prerequisites_selected(problem, i, selected) {
            match chosen {
              None => chosen = Some(i)
              Some(current) =>
                if better_candidate(
                    i, current, problem, baseline, remaining, downstream_priority,
                  ) {
                  chosen = Some(i)
                }
            }
          }
        }
        match chosen {
          Some(value) => value
          None => abort("validated DAG has no ready task")
        }
      }
    }
    let task = problem.tasks[index]
    let mut earliest = 0
    for edge in problem.dependencies {
      if edge.task_id == task.id {
        let prerequisite = match
          task_index(problem.tasks, edge.prerequisite_id) {
          Some(value) => value
          None => abort("validated prerequisite disappeared")
        }
        if completion[prerequisite] > earliest {
          earliest = completion[prerequisite]
        }
      }
    }
    let start = earliest_slot(task, earliest, schedule)
    let finish = checked_finish(start, task.duration)
    schedule.push({
      task_id: task.id,
      resource_id: task.resource_id,
      start,
      finish,
    })
    completion[index] = finish
    selected[index] = true
  }
  evaluate_schedule(problem~, schedule~, algorithm=baseline_name(baseline))
}
