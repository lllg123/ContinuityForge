///|
fn task(id : String, duration : Int, resource : String) -> @scheduling.Task {
  try! @scheduling.Task::new(id~, duration~, priority=0, resource_id=resource)
}

///|
fn resource(id : String) -> @scheduling.Resource {
  try! @scheduling.Resource::new(id~)
}

///|
fn edge(task_id : String, prerequisite_id : String) -> @scheduling.Dependency {
  try! @scheduling.Dependency::new(task_id~, prerequisite_id~)
}

///|
fn slot(
  id : String,
  resource : String,
  start : Int,
  finish : Int,
) -> @scheduling.ScheduleEntry {
  try! @scheduling.ScheduleEntry::new(
    task_id=id,
    resource_id=resource,
    start~,
    finish~,
  )
}

///|
fn problem(
  tasks : Array[@scheduling.Task],
  dependencies : Array[@scheduling.Dependency],
  resources : Array[@scheduling.Resource],
  target : Int?,
) -> @scheduling.SchedulingProblem {
  try! @scheduling.SchedulingProblem::new(
    tasks~,
    dependencies~,
    constraints=try! @scheduling.Constraints::new(
      resources~,
      target_makespan=target,
    ),
  )
}

///|
test "one interface evaluates incident recovery and CI pipeline schedules" {
  let recovery = problem(
    [
      task("restore-db", 10, "database"),
      task("restore-api", 20, "compute"),
      task("restore-worker", 15, "compute"),
    ],
    [edge("restore-api", "restore-db")],
    [resource("database"), resource("compute")],
    Some(45),
  )
  let recovery_result = try! @scheduling.evaluate_schedule(
    problem=recovery,
    schedule=[
      slot("restore-db", "database", 0, 10),
      slot("restore-api", "compute", 10, 30),
      slot("restore-worker", "compute", 30, 45),
    ],
    algorithm="external-candidate",
  )
  assert_eq(recovery_result.makespan, 45)
  assert_eq(recovery_result.explanation.algorithm, "external-candidate")
  let pipeline = problem(
    [
      task("compile", 8, "runner-a"),
      task("lint", 4, "runner-b"),
      task("test", 5, "runner-a"),
    ],
    [edge("test", "compile")],
    [resource("runner-a"), resource("runner-b")],
    Some(14),
  )
  let pipeline_result = try! @scheduling.evaluate_schedule(
    problem=pipeline,
    schedule=[
      slot("compile", "runner-a", 0, 8),
      slot("lint", "runner-b", 0, 4),
      slot("test", "runner-a", 8, 13),
    ],
    algorithm="external-candidate",
  )
  assert_eq(pipeline_result.makespan, 13)
}

///|
test "empty problem and schedule have zero makespan" {
  let empty = problem([], [], [], Some(0))
  let result = try! @scheduling.evaluate_schedule(
    problem=empty,
    schedule=[],
    algorithm="empty-case",
  )
  assert_eq(result.makespan, 0)
}

///|
test "problem rejects duplicate tasks and unavailable resources" {
  try
    @scheduling.SchedulingProblem::new(
      tasks=[task("a", 1, "r"), task("a", 2, "r")],
      dependencies=[],
      constraints=try! @scheduling.Constraints::new(
        resources=[resource("r")],
        target_makespan=None,
      ),
    )
  catch {
    @scheduling.SchedulingError::InvalidTask(_) => ()
    _ => fail("wrong duplicate task error")
  } noraise {
    _ => fail("expected duplicate task error")
  }
  try
    @scheduling.SchedulingProblem::new(
      tasks=[task("a", 1, "missing")],
      dependencies=[],
      constraints=try! @scheduling.Constraints::new(
        resources=[resource("r")],
        target_makespan=None,
      ),
    )
  catch {
    @scheduling.SchedulingError::InvalidResource(_) => ()
    _ => fail("wrong missing resource error")
  } noraise {
    _ => fail("expected missing resource error")
  }
}

///|
test "problem rejects missing dependencies and cycles" {
  let constraints = try! @scheduling.Constraints::new(
    resources=[resource("r")],
    target_makespan=None,
  )
  try
    @scheduling.SchedulingProblem::new(
      tasks=[task("a", 1, "r")],
      dependencies=[edge("a", "missing")],
      constraints~,
    )
  catch {
    @scheduling.SchedulingError::InvalidDependency(_) => ()
    _ => fail("wrong missing prerequisite error")
  } noraise {
    _ => fail("expected missing prerequisite error")
  }
  try
    @scheduling.SchedulingProblem::new(
      tasks=[task("a", 1, "r"), task("b", 1, "r")],
      dependencies=[edge("a", "b"), edge("b", "a")],
      constraints~,
    )
  catch {
    @scheduling.SchedulingError::InvalidDependency(message) =>
      inspect(message, content="dependency cycle")
    _ => fail("wrong cycle error")
  } noraise {
    _ => fail("expected cycle error")
  }
}

///|
test "schedule rejects overlap, early dependents and wrong durations" {
  let p = problem(
    [task("a", 5, "r"), task("b", 4, "r")],
    [edge("b", "a")],
    [resource("r")],
    None,
  )
  try
    @scheduling.validate_schedule(p, [
      slot("a", "r", 0, 5),
      slot("b", "r", 4, 8),
    ])
  catch {
    @scheduling.SchedulingError::InvalidSchedule(_) => ()
    _ => fail("wrong overlap error")
  } noraise {
    _ => fail("expected overlap error")
  }
  let parallel = problem(
    [task("a", 5, "r1"), task("b", 4, "r2")],
    [edge("b", "a")],
    [resource("r1"), resource("r2")],
    None,
  )
  try
    @scheduling.validate_schedule(parallel, [
      slot("a", "r1", 0, 5),
      slot("b", "r2", 0, 4),
    ])
  catch {
    @scheduling.SchedulingError::InvalidSchedule(_) => ()
    _ => fail("wrong dependency timing error")
  } noraise {
    _ => fail("expected dependency timing error")
  }
  try
    @scheduling.validate_schedule(parallel, [
      slot("a", "r1", 0, 4),
      slot("b", "r2", 5, 9),
    ])
  catch {
    @scheduling.SchedulingError::InvalidSchedule(_) => ()
    _ => fail("wrong duration error")
  } noraise {
    _ => fail("expected duration error")
  }
}

///|
test "schedule rejects missing tasks and an unmet target" {
  let p = problem([task("a", 5, "r")], [], [resource("r")], Some(5))
  try @scheduling.validate_schedule(p, []) catch {
    @scheduling.SchedulingError::InvalidSchedule(_) => ()
    _ => fail("wrong missing task error")
  } noraise {
    _ => fail("expected missing task error")
  }
  try @scheduling.validate_schedule(p, [slot("a", "r", 1, 6)]) catch {
    @scheduling.SchedulingError::InvalidSchedule(message) =>
      inspect(message, content="makespan 6 exceeds target 5")
    _ => fail("wrong target error")
  } noraise {
    _ => fail("expected target error")
  }
}
