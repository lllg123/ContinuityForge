///|
/// A structured, solver-independent constraint violation. Optional fields
/// identify the relevant task, resource and interval when available.
pub(all) struct ConstraintViolation {
  kind : String
  task_id : String?
  resource_id : String?
  start : Int?
  finish : Int?
  message : String
}

///|
fn violation(
  kind : String,
  task_id : String?,
  resource_id : String?,
  start : Int?,
  finish : Int?,
  message : String,
) -> ConstraintViolation {
  { kind, task_id, resource_id, start, finish, message, }
}

///|
fn rcpsp_task_index(tasks : Array[RcpspTask], id : String) -> Int? {
  for i, task in tasks {
    if task.id == id {
      return Some(i)
    }
  }
  None
}

///|
fn rcpsp_resource_index(
  resources : Array[RenewableResource],
  id : String,
) -> Int? {
  for i, resource in resources {
    if resource.id == id {
      return Some(i)
    }
  }
  None
}

///|
fn demand_for(task : RcpspTask, resource_id : String) -> Int {
  for demand in task.demands {
    if demand.resource_id == resource_id {
      return demand.amount
    }
  }
  0
}

///|
/// Checks the full public record, including mutations after construction.
pub fn inspect_rcpsp_problem(
  problem : RcpspProblem,
) -> Array[ConstraintViolation] {
  let issues : Array[ConstraintViolation] = []
  match problem.target_makespan {
    Some(value) =>
      if value < 0 {
        issues.push(
          violation(
            "target",
            None,
            None,
            None,
            None,
            "target_makespan cannot be negative",
          ),
        )
      }
    None => ()
  }
  for i, resource in problem.resources {
    if resource.id == "" || resource.capacity <= 0 {
      issues.push(
        violation(
          "resource",
          None,
          Some(resource.id),
          None,
          None,
          "resource needs a nonempty id and positive capacity",
        ),
      )
    }
    for j in 0..<i {
      if problem.resources[j].id == resource.id {
        issues.push(
          violation(
            "resource",
            None,
            Some(resource.id),
            None,
            None,
            "duplicate resource",
          ),
        )
      }
    }
  }
  for i, task in problem.tasks {
    if task.id == "" ||
      task.duration < 0 ||
      (task.duration == 0 && !task.demands.is_empty()) {
      issues.push(
        violation(
          "task",
          Some(task.id),
          None,
          None,
          None,
          "invalid task id, duration, or milestone demand",
        ),
      )
    }
    if task.release_time < 0 || task.duration > 2147483647 - task.release_time {
      issues.push(
        violation(
          "time_range",
          Some(task.id),
          None,
          None,
          None,
          "release time or finish overflows integer range",
        ),
      )
    }
    match task.deadline {
      Some(value) =>
        if value < task.release_time {
          issues.push(
            violation(
              "deadline",
              Some(task.id),
              None,
              None,
              None,
              "deadline precedes release time",
            ),
          )
        }
      None => ()
    }
    for j in 0..<i {
      if problem.tasks[j].id == task.id {
        issues.push(
          violation("task", Some(task.id), None, None, None, "duplicate task"),
        )
      }
    }
    for j, demand in task.demands {
      let resource = match
        rcpsp_resource_index(problem.resources, demand.resource_id) {
        Some(index) => Some(problem.resources[index])
        None => None
      }
      if demand.resource_id == "" || demand.amount <= 0 {
        issues.push(
          violation(
            "demand",
            Some(task.id),
            Some(demand.resource_id),
            None,
            None,
            "resource demand must be positive",
          ),
        )
      }
      match resource {
        Some(value) =>
          if demand.amount > value.capacity {
            issues.push(
              violation(
                "demand",
                Some(task.id),
                Some(demand.resource_id),
                None,
                None,
                "task demand exceeds capacity",
              ),
            )
          }
        None =>
          issues.push(
            violation(
              "resource",
              Some(task.id),
              Some(demand.resource_id),
              None,
              None,
              "unknown resource",
            ),
          )
      }
      for k in 0..<j {
        if task.demands[k].resource_id == demand.resource_id {
          issues.push(
            violation(
              "demand",
              Some(task.id),
              Some(demand.resource_id),
              None,
              None,
              "duplicate resource demand",
            ),
          )
        }
      }
    }
  }
  let indegree : Array[Int] = []
  for _ in problem.tasks {
    indegree.push(0)
  }
  let mut edges_valid = true
  for i, edge in problem.dependencies {
    if edge.task_id == edge.prerequisite_id ||
      rcpsp_task_index(problem.tasks, edge.task_id) is None ||
      rcpsp_task_index(problem.tasks, edge.prerequisite_id) is None {
      issues.push(
        violation(
          "dependency",
          Some(edge.task_id),
          None,
          None,
          None,
          "invalid dependency endpoint",
        ),
      )
      edges_valid = false
    } else {
      let dependent = match rcpsp_task_index(problem.tasks, edge.task_id) {
        Some(value) => value
        None => abort("checked dependent disappeared")
      }
      indegree[dependent] = indegree[dependent] + 1
    }
    for j in 0..<i {
      if problem.dependencies[j].task_id == edge.task_id &&
        problem.dependencies[j].prerequisite_id == edge.prerequisite_id {
        issues.push(
          violation(
            "dependency",
            Some(edge.task_id),
            None,
            None,
            None,
            "duplicate dependency",
          ),
        )
      }
    }
  }
  if edges_valid {
    let ready : Array[Int] = []
    for i, degree in indegree {
      if degree == 0 {
        ready.push(i)
      }
    }
    let mut cursor = 0
    while cursor < ready.length() {
      let id = problem.tasks[ready[cursor]].id
      cursor = cursor + 1
      for edge in problem.dependencies {
        if edge.prerequisite_id == id {
          let dependent = match rcpsp_task_index(problem.tasks, edge.task_id) {
            Some(value) => value
            None => abort("checked dependent disappeared")
          }
          indegree[dependent] = indegree[dependent] - 1
          if indegree[dependent] == 0 {
            ready.push(dependent)
          }
        }
      }
    }
    if ready.length() != problem.tasks.length() {
      issues.push(
        violation("dependency", None, None, None, None, "dependency cycle"),
      )
    }
  }
  issues
}

///|
pub fn validate_rcpsp_problem(
  problem : RcpspProblem,
) -> Unit raise SchedulingError {
  let issues = inspect_rcpsp_problem(problem)
  if !issues.is_empty() {
    raise SchedulingError::InvalidConstraint(issues[0].message)
  }
}

///|
/// Independent feasibility checker for generated or externally imported
/// schedules. At time t, [start, finish) excludes tasks finishing at t.
pub fn inspect_rcpsp_schedule(
  problem : RcpspProblem,
  schedule : Array[RcpspScheduleEntry],
) -> Array[ConstraintViolation] {
  let issues = inspect_rcpsp_problem(problem)
  if !issues.is_empty() {
    return issues
  }
  let mut structural_invalid = false
  if schedule.length() != problem.tasks.length() {
    structural_invalid = true
    issues.push(
      violation(
        "completeness",
        None,
        None,
        None,
        None,
        "schedule must contain every task once",
      ),
    )
  }
  for i, entry in schedule {
    let task = match rcpsp_task_index(problem.tasks, entry.task_id) {
      Some(index) => Some(problem.tasks[index])
      None => None
    }
    match task {
      None => {
        structural_invalid = true
        issues.push(
          violation(
            "completeness",
            Some(entry.task_id),
            None,
            Some(entry.start),
            Some(entry.finish),
            "unknown scheduled task",
          ),
        )
      }
      Some(value) => {
        if entry.start < 0 ||
          entry.finish < entry.start ||
          entry.finish - entry.start != value.duration {
          structural_invalid = true
          issues.push(
            violation(
              "duration",
              Some(entry.task_id),
              None,
              Some(entry.start),
              Some(entry.finish),
              "invalid task interval",
            ),
          )
        }
        if entry.start < value.release_time {
          issues.push(
            violation(
              "release_time",
              Some(entry.task_id),
              None,
              Some(entry.start),
              Some(entry.finish),
              "task starts before release time",
            ),
          )
        }
        match value.deadline {
          Some(deadline) =>
            if entry.finish > deadline {
              issues.push(
                violation(
                  "deadline",
                  Some(entry.task_id),
                  None,
                  Some(entry.start),
                  Some(entry.finish),
                  "task misses hard deadline",
                ),
              )
            }
          None => ()
        }
      }
    }
    for j in 0..<i {
      if schedule[j].task_id == entry.task_id {
        structural_invalid = true
        issues.push(
          violation(
            "completeness",
            Some(entry.task_id),
            None,
            Some(entry.start),
            Some(entry.finish),
            "duplicate scheduled task",
          ),
        )
      }
    }
  }
  if structural_invalid {
    return issues
  }
  for edge in problem.dependencies {
    let mut dependent : RcpspScheduleEntry? = None
    let mut prerequisite : RcpspScheduleEntry? = None
    for entry in schedule {
      if entry.task_id == edge.task_id {
        dependent = Some(entry)
      }
      if entry.task_id == edge.prerequisite_id {
        prerequisite = Some(entry)
      }
    }
    match (dependent, prerequisite) {
      (Some(task), Some(before)) =>
        if task.start < before.finish {
          issues.push(
            violation(
              "precedence",
              Some(edge.task_id),
              None,
              Some(task.start),
              Some(task.finish),
              "task starts before prerequisite finishes",
            ),
          )
        }
      _ => abort("checked schedule endpoint disappeared")
    }
  }
  let mut makespan = 0
  for entry in schedule {
    if entry.finish > makespan {
      makespan = entry.finish
    }
  }
  match problem.target_makespan {
    Some(target) =>
      if makespan > target {
        issues.push(
          violation(
            "target",
            None,
            None,
            Some(0),
            Some(makespan),
            "makespan exceeds target",
          ),
        )
      }
    None => ()
  }
  for resource in problem.resources {
    for anchor in schedule {
      let time = anchor.start
      let mut used = 0
      for entry in schedule {
        if entry.start <= time && time < entry.finish {
          let task = match rcpsp_task_index(problem.tasks, entry.task_id) {
            Some(index) => problem.tasks[index]
            None => abort("checked schedule task disappeared")
          }
          let amount = demand_for(task, resource.id)
          if amount > resource.capacity - used {
            issues.push(
              violation(
                "capacity",
                Some(entry.task_id),
                Some(resource.id),
                Some(time),
                Some(entry.finish),
                "renewable resource capacity exceeded",
              ),
            )
            break
          }
          used = used + amount
        }
      }
    }
  }
  issues
}

///|
pub fn validate_rcpsp_schedule(
  problem : RcpspProblem,
  schedule : Array[RcpspScheduleEntry],
) -> Unit raise SchedulingError {
  let issues = inspect_rcpsp_schedule(problem, schedule)
  if !issues.is_empty() {
    raise SchedulingError::InvalidSchedule(issues[0].message)
  }
}
