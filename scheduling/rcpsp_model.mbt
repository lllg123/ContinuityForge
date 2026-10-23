///|
/// One renewable resource. Capacity is available again when a task finishes.
pub(all) struct RenewableResource {
  id : String
  capacity : Int
}

///|
pub fn RenewableResource::new(
  id~ : String,
  capacity~ : Int,
) -> RenewableResource raise SchedulingError {
  if id == "" || capacity <= 0 {
    raise SchedulingError::InvalidResource(
      "renewable resource needs a nonempty id and positive capacity",
    )
  }
  { id, capacity, }
}

///|
/// A positive amount reserved for the task's entire execution interval.
pub(all) struct ResourceDemand {
  resource_id : String
  amount : Int
}

///|
pub fn ResourceDemand::new(
  resource_id~ : String,
  amount~ : Int,
) -> ResourceDemand raise SchedulingError {
  if resource_id == "" || amount <= 0 {
    raise SchedulingError::InvalidResource(
      "resource demand needs a nonempty id and positive amount",
    )
  }
  { resource_id, amount, }
}

///|
/// Single-mode, non-preemptive task. Zero duration is reserved for an empty
/// milestone (for example a PSPLIB source or sink dummy task).
pub(all) struct RcpspTask {
  id : String
  duration : Int
  priority : Int
  demands : Array[ResourceDemand]
  release_time : Int
  deadline : Int?
}

///|
pub fn RcpspTask::new(
  id~ : String,
  duration~ : Int,
  priority~ : Int,
  demands~ : Array[ResourceDemand],
  release_time~ : Int,
  deadline~ : Int?,
) -> RcpspTask raise SchedulingError {
  if id == "" || duration < 0 || (duration == 0 && !demands.is_empty()) {
    raise SchedulingError::InvalidTask(
      "invalid RCPSP task id, duration, or milestone demand",
    )
  }
  if release_time < 0 || duration > 2147483647 - release_time {
    raise SchedulingError::InvalidTask(
      "invalid RCPSP release time or time range",
    )
  }
  match deadline {
    Some(value) =>
      if value < release_time {
        raise SchedulingError::InvalidTask("deadline precedes release time")
      }
    None => ()
  }
  { id, duration, priority, demands, release_time, deadline, }
}

///|
/// An integer-time RCPSP subset. Dependencies reuse the existing edge type.
pub(all) struct RcpspProblem {
  tasks : Array[RcpspTask]
  dependencies : Array[Dependency]
  resources : Array[RenewableResource]
  target_makespan : Int?
}

///|
pub fn RcpspProblem::new(
  tasks~ : Array[RcpspTask],
  dependencies~ : Array[Dependency],
  resources~ : Array[RenewableResource],
  target_makespan~ : Int?,
) -> RcpspProblem raise SchedulingError {
  let problem = { tasks, dependencies, resources, target_makespan, }
  validate_rcpsp_problem(problem)
  problem
}

///|
/// One whole execution interval; resource demands are read from its task.
pub(all) struct RcpspScheduleEntry {
  task_id : String
  start : Int
  finish : Int
}

///|
pub fn RcpspScheduleEntry::new(
  task_id~ : String,
  start~ : Int,
  finish~ : Int,
) -> RcpspScheduleEntry raise SchedulingError {
  if task_id == "" || start < 0 || finish < start {
    raise SchedulingError::InvalidSchedule("invalid RCPSP schedule entry")
  }
  { task_id, start, finish, }
}

///|
/// Explicit legacy mapping: one resource with capacity one and demand one.
pub fn upgrade_exclusive_problem(
  problem : SchedulingProblem,
) -> RcpspProblem raise SchedulingError {
  validate_problem(problem)
  let resources : Array[RenewableResource] = []
  for resource in problem.constraints.resources {
    resources.push(RenewableResource::new(id=resource.id, capacity=1))
  }
  let tasks : Array[RcpspTask] = []
  for task in problem.tasks {
    tasks.push(
      RcpspTask::new(
        id=task.id,
        duration=task.duration,
        priority=task.priority,
        demands=[ResourceDemand::new(resource_id=task.resource_id, amount=1)],
        release_time=0,
        deadline=None,
      ),
    )
  }
  RcpspProblem::new(
    tasks~,
    dependencies=problem.dependencies,
    resources~,
    target_makespan=problem.constraints.target_makespan,
  )
}
