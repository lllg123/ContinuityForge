///|
/// Longest dependency-only path. Resource contention can make the actual
/// makespan larger; this path is a lower bound, not a final schedule.
pub(all) struct CriticalPathSummary {
  task_ids : Array[String]
  duration : Int
}

///|
pub fn critical_path(
  problem : SchedulingProblem,
) -> CriticalPathSummary raise SchedulingError {
  validate_problem(problem)
  let order = stable_order(problem)
  let (remaining, _) = path_metrics(problem, order)
  let mut start : Int? = None
  for index, value in remaining {
    match start {
      None => start = Some(index)
      Some(current) => if value > remaining[current] { start = Some(index) }
    }
  }
  let task_ids : Array[String] = []
  let mut duration = 0
  let mut current = start
  while current is Some(_) {
    let index = match current {
      Some(value) => value
      None => abort("loop guard lost current task")
    }
    let task = problem.tasks[index]
    task_ids.push(task.id)
    duration = duration + task.duration
    let mut next : Int? = None
    for edge in problem.dependencies {
      if edge.prerequisite_id == task.id {
        let dependent = match task_index(problem.tasks, edge.task_id) {
          Some(value) => value
          None => abort("validated dependent disappeared")
        }
        if remaining[dependent] + task.duration == remaining[index] &&
          next is None {
          next = Some(dependent)
        }
      }
    }
    current = next
  }
  { task_ids, duration, }
}
