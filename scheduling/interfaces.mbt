///|
/// A unit-capacity, non-preemptive scheduling problem. Every task names one
/// resource, dependencies form a DAG, and the objective is minimum makespan.
pub(all) struct SchedulingProblem {
  tasks : Array[Task]
  dependencies : Array[Dependency]
  constraints : Constraints
}

///|
fn task_index(tasks : Array[Task], id : String) -> Int? {
  for i, task in tasks {
    if task.id == id {
      return Some(i)
    }
  }
  None
}

///|
fn resource_exists(resources : Array[Resource], id : String) -> Bool {
  for resource in resources {
    if resource.id == id {
      return true
    }
  }
  false
}

///|
/// Validates task identities, durations, resources, edges and acyclicity.
/// Revalidation is intentional: public records and their arrays are mutable.
pub fn validate_problem(
  problem : SchedulingProblem,
) -> Unit raise SchedulingError {
  let tasks = problem.tasks
  let resources = problem.constraints.resources
  match problem.constraints.target_makespan {
    Some(value) =>
      if value < 0 {
        raise SchedulingError::InvalidConstraint(
          "target_makespan cannot be negative",
        )
      }
    None => ()
  }
  for i, resource in resources {
    if resource.id == "" {
      raise SchedulingError::InvalidResource("resource id cannot be empty")
    }
    for j in 0..<i {
      if resources[j].id == resource.id {
        raise SchedulingError::InvalidResource(
          "duplicate resource: \{resource.id}",
        )
      }
    }
  }
  for i, task in tasks {
    if task.id == "" || task.duration <= 0 || task.resource_id == "" {
      raise SchedulingError::InvalidTask("invalid task: \{task.id}")
    }
    if !resource_exists(resources, task.resource_id) {
      raise SchedulingError::InvalidResource(
        "resource unavailable for \{task.id}: \{task.resource_id}",
      )
    }
    for j in 0..<i {
      if tasks[j].id == task.id {
        raise SchedulingError::InvalidTask("duplicate task: \{task.id}")
      }
    }
  }
  let indegree : Array[Int] = []
  for _ in tasks {
    indegree.push(0)
  }
  for i, edge in problem.dependencies {
    if edge.task_id == edge.prerequisite_id {
      raise SchedulingError::InvalidDependency("task cannot depend on itself")
    }
    let task = match task_index(tasks, edge.task_id) {
      Some(value) => value
      None =>
        raise SchedulingError::InvalidDependency(
          "missing task: \{edge.task_id}",
        )
    }
    if task_index(tasks, edge.prerequisite_id) is None {
      raise SchedulingError::InvalidDependency(
        "missing prerequisite: \{edge.prerequisite_id}",
      )
    }
    for j in 0..<i {
      if problem.dependencies[j].task_id == edge.task_id &&
        problem.dependencies[j].prerequisite_id == edge.prerequisite_id {
        raise SchedulingError::InvalidDependency(
          "duplicate dependency: \{edge.prerequisite_id} -> \{edge.task_id}",
        )
      }
    }
    indegree[task] = indegree[task] + 1
  }
  let ready : Array[Int] = []
  for i, degree in indegree {
    if degree == 0 {
      ready.push(i)
    }
  }
  let mut cursor = 0
  while cursor < ready.length() {
    let finished = tasks[ready[cursor]].id
    cursor = cursor + 1
    for edge in problem.dependencies {
      if edge.prerequisite_id == finished {
        let dependent = match task_index(tasks, edge.task_id) {
          Some(value) => value
          None => abort("validated task disappeared")
        }
        indegree[dependent] = indegree[dependent] - 1
        if indegree[dependent] == 0 {
          ready.push(dependent)
        }
      }
    }
  }
  if ready.length() != tasks.length() {
    raise SchedulingError::InvalidDependency("dependency cycle")
  }
}

///|
/// Creates a validated problem without changing the existing recovery API.
pub fn SchedulingProblem::new(
  tasks~ : Array[Task],
  dependencies~ : Array[Dependency],
  constraints~ : Constraints,
) -> SchedulingProblem raise SchedulingError {
  let problem = { tasks, dependencies, constraints, }
  validate_problem(problem)
  problem
}

///|
fn entry_index(entries : Array[ScheduleEntry], task_id : String) -> Int? {
  for i, entry in entries {
    if entry.task_id == task_id {
      return Some(i)
    }
  }
  None
}

///|
/// Independently checks a proposed schedule against the unified constraints.
/// An empty problem accepts only an empty schedule with makespan zero.
pub fn validate_schedule(
  problem : SchedulingProblem,
  schedule : Array[ScheduleEntry],
) -> Unit raise SchedulingError {
  validate_problem(problem)
  if schedule.length() != problem.tasks.length() {
    raise SchedulingError::InvalidSchedule(
      "schedule must contain every task once",
    )
  }
  let mut makespan = 0
  for i, entry in schedule {
    let task = match task_index(problem.tasks, entry.task_id) {
      Some(index) => problem.tasks[index]
      None =>
        raise SchedulingError::InvalidSchedule(
          "unknown scheduled task: \{entry.task_id}",
        )
    }
    if entry.resource_id != task.resource_id ||
      entry.start < 0 ||
      entry.finish <= entry.start ||
      entry.finish - entry.start != task.duration {
      raise SchedulingError::InvalidSchedule(
        "invalid timing or resource for \{entry.task_id}",
      )
    }
    for j in 0..<i {
      let other = schedule[j]
      if other.task_id == entry.task_id {
        raise SchedulingError::InvalidSchedule(
          "duplicate scheduled task: \{entry.task_id}",
        )
      }
      if other.resource_id == entry.resource_id &&
        entry.start < other.finish &&
        other.start < entry.finish {
        raise SchedulingError::InvalidSchedule(
          "resource overlap: \{entry.resource_id}",
        )
      }
    }
    if entry.finish > makespan {
      makespan = entry.finish
    }
  }
  for edge in problem.dependencies {
    let task_entry = match entry_index(schedule, edge.task_id) {
      Some(index) => schedule[index]
      None => abort("validated schedule task disappeared")
    }
    let prerequisite_entry = match entry_index(schedule, edge.prerequisite_id) {
      Some(index) => schedule[index]
      None => abort("validated schedule prerequisite disappeared")
    }
    if task_entry.start < prerequisite_entry.finish {
      raise SchedulingError::InvalidSchedule(
        "prerequisite unfinished: \{edge.prerequisite_id} -> \{edge.task_id}",
      )
    }
  }
  match problem.constraints.target_makespan {
    Some(target) =>
      if makespan > target {
        raise SchedulingError::InvalidSchedule(
          "makespan \{makespan} exceeds target \{target}",
        )
      }
    None => ()
  }
}

///|
/// Checks an algorithm's candidate and computes its actual makespan.
/// `algorithm` is a provenance label; this function does not optimize.
pub fn evaluate_schedule(
  problem~ : SchedulingProblem,
  schedule~ : Array[ScheduleEntry],
  algorithm~ : String,
) -> AnalysisResult raise SchedulingError {
  if algorithm == "" {
    raise SchedulingError::InvalidSchedule("algorithm label cannot be empty")
  }
  validate_schedule(problem, schedule)
  let mut makespan = 0
  for entry in schedule {
    if entry.finish > makespan {
      makespan = entry.finish
    }
  }
  {
    schedule,
    makespan,
    explanation: {
      algorithm,
      details: [
        "validated \{problem.tasks.length()} tasks",
        "exclusive unit-capacity resources; non-preemptive execution",
      ],
    },
  }
}
