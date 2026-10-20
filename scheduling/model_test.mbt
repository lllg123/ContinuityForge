///|
test "task and resource names are independent of application domain" {
  let recovery = try! @scheduling.Task::new(
    id="restore-db",
    duration=10,
    priority=3,
    resource_id="database",
  )
  let pipeline = try! @scheduling.Task::new(
    id="compile",
    duration=10,
    priority=3,
    resource_id="runner",
  )
  assert_eq(recovery.duration, pipeline.duration)
  assert_eq(recovery.resource_id, "database")
  assert_eq(pipeline.resource_id, "runner")
  let edge = try! @scheduling.Dependency::new(
    task_id="test",
    prerequisite_id="compile",
  )
  assert_eq(edge.prerequisite_id, pipeline.id)
}

///|
test "invalid task fields and self dependency are rejected" {
  try
    @scheduling.Task::new(id="", duration=2, priority=0, resource_id="runner")
  catch {
    @scheduling.SchedulingError::InvalidTask(_) => ()
    _ => fail("wrong task error")
  } noraise {
    _ => fail("expected invalid task")
  }
  try
    @scheduling.Task::new(id="a", duration=0, priority=0, resource_id="runner")
  catch {
    @scheduling.SchedulingError::InvalidTask(_) => ()
    _ => fail("wrong duration error")
  } noraise {
    _ => fail("expected invalid duration")
  }
  try @scheduling.Dependency::new(task_id="a", prerequisite_id="a") catch {
    @scheduling.SchedulingError::InvalidDependency(_) => ()
    _ => fail("wrong dependency error")
  } noraise {
    _ => fail("expected self dependency error")
  }
}

///|
test "resource, target, and entry have basic shape validation" {
  let resource = try! @scheduling.Resource::new(id="runner")
  let constraints = try! @scheduling.Constraints::new(
    resources=[resource],
    target_makespan=Some(0),
  )
  assert_eq(constraints.resources[0].id, "runner")
  let entry = try! @scheduling.ScheduleEntry::new(
    task_id="compile",
    resource_id="runner",
    start=0,
    finish=5,
  )
  assert_eq(entry.finish, 5)
  try
    @scheduling.Constraints::new(resources=[resource], target_makespan=Some(-1))
  catch {
    @scheduling.SchedulingError::InvalidConstraint(_) => ()
    _ => fail("wrong target error")
  } noraise {
    _ => fail("expected invalid target")
  }
}
