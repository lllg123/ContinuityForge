///|
/// Input and result validation errors for domain-independent scheduling.
pub(all) suberror SchedulingError {
  InvalidTask(String)
  InvalidResource(String)
  InvalidDependency(String)
  InvalidConstraint(String)
  InvalidSchedule(String)
}

///|
/// One non-preemptive task requiring exactly one exclusive resource.
/// Duration is a positive number of caller-defined time units.
pub(all) struct Task {
  id : String
  duration : Int
  priority : Int
  resource_id : String
}

///|
pub fn Task::new(
  id~ : String,
  duration~ : Int,
  priority~ : Int,
  resource_id~ : String,
) -> Task raise SchedulingError {
  if id == "" {
    raise SchedulingError::InvalidTask("task id cannot be empty")
  }
  if duration <= 0 {
    raise SchedulingError::InvalidTask("task duration must be positive")
  }
  if resource_id == "" {
    raise SchedulingError::InvalidTask("task resource_id cannot be empty")
  }
  { id, duration, priority, resource_id, }
}

///|
/// `task_id` may start only after `prerequisite_id` has finished.
pub(all) struct Dependency {
  task_id : String
  prerequisite_id : String
}

///|
pub fn Dependency::new(
  task_id~ : String,
  prerequisite_id~ : String,
) -> Dependency raise SchedulingError {
  if task_id == "" || prerequisite_id == "" {
    raise SchedulingError::InvalidDependency(
      "dependency endpoint cannot be empty",
    )
  }
  if task_id == prerequisite_id {
    raise SchedulingError::InvalidDependency("task cannot depend on itself")
  }
  { task_id, prerequisite_id, }
}

///|
/// One exclusive resource with unit capacity.
pub(all) struct Resource {
  id : String
}

///|
pub fn Resource::new(id~ : String) -> Resource raise SchedulingError {
  if id == "" {
    raise SchedulingError::InvalidResource("resource id cannot be empty")
  }
  { id, }
}

///|
/// Available resources and an optional maximum makespan.
pub(all) struct Constraints {
  resources : Array[Resource]
  target_makespan : Int?
}

///|
pub fn Constraints::new(
  resources~ : Array[Resource],
  target_makespan~ : Int?,
) -> Constraints raise SchedulingError {
  match target_makespan {
    Some(value) =>
      if value < 0 {
        raise SchedulingError::InvalidConstraint(
          "target_makespan cannot be negative",
        )
      }
    None => ()
  }
  { resources, target_makespan, }
}

///|
/// One task's start and finish in a non-preemptive schedule.
pub(all) struct ScheduleEntry {
  task_id : String
  resource_id : String
  start : Int
  finish : Int
}

///|
pub fn ScheduleEntry::new(
  task_id~ : String,
  resource_id~ : String,
  start~ : Int,
  finish~ : Int,
) -> ScheduleEntry raise SchedulingError {
  if task_id == "" || resource_id == "" || start < 0 || finish <= start {
    raise SchedulingError::InvalidSchedule("invalid schedule entry")
  }
  { task_id, resource_id, start, finish, }
}

///|
/// Human-readable provenance for a computed analysis result.
pub(all) struct Explanation {
  algorithm : String
  details : Array[String]
}

///|
/// A schedule and its makespan; feasibility is checked by validate_schedule.
pub(all) struct AnalysisResult {
  schedule : Array[ScheduleEntry]
  makespan : Int
  explanation : Explanation
}
