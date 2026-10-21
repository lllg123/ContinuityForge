///|
test "chain, independent resources, and shared resource agree with exact reference" {
  let cases : Array[@scheduling.SchedulingProblem] = [
    problem(
      [task("a", 2, "r1"), task("b", 3, "r2"), task("c", 4, "r1")],
      [edge("b", "a"), edge("c", "b")],
      [resource("r1"), resource("r2")],
      None,
    ),
    problem(
      [task("a", 4, "r1"), task("b", 6, "r2")],
      [],
      [resource("r1"), resource("r2")],
      None,
    ),
    problem(
      [task("a", 4, "r1"), task("b", 6, "r1")],
      [],
      [resource("r1")],
      None,
    ),
  ]
  let expected = [9, 6, 10]
  for i, p in cases {
    let reference = try! @scheduling.exact_reference(p, 100)
    assert_true(reference.proven_optimal)
    let optimum = match reference.best {
      Some(value) => value
      None => fail("missing exact result")
    }
    assert_eq(optimum.makespan, expected[i])
    for
      baseline in [
        @scheduling.Baseline::StableTopological,
        @scheduling.Baseline::RecoveryHeuristic,
        @scheduling.Baseline::CriticalPath,
      ] {
      let result = try! @scheduling.run_baseline(p, baseline)
      try! @scheduling.validate_schedule(p, result.schedule)
      assert_eq(result.makespan, optimum.makespan)
    }
  }
}

///|
test "exact result proves a requested window impossible" {
  let p = problem([task("only", 5, "r")], [], [resource("r")], Some(4))
  let reference = try! @scheduling.exact_reference(p, 2)
  assert_true(reference.proven_optimal)
  let optimum = match reference.best {
    Some(value) => value
    None => fail("missing exact result")
  }
  assert_eq(optimum.makespan, 5)
  try @scheduling.validate_schedule(p, optimum.schedule) catch {
    @scheduling.SchedulingError::InvalidSchedule(message) =>
      inspect(message, content="makespan 5 exceeds target 4")
    _ => fail("wrong target error")
  } noraise {
    _ => fail("target should be impossible")
  }
}

///|
test "validator rechecks mutable input and rejects duplicate schedule entries" {
  let p = problem([task("a", 2, "r")], [], [resource("r")], None)
  p.tasks.push({ id: "bad", duration: 0, priority: 0, resource_id: "r", })
  try
    @scheduling.run_baseline(p, @scheduling.Baseline::StableTopological)
  catch {
    @scheduling.SchedulingError::InvalidTask(_) => ()
    _ => fail("wrong mutable input error")
  } noraise {
    _ => fail("expected invalid mutated task")
  }
  let valid = problem(
    [task("a", 2, "r"), task("b", 3, "r")],
    [],
    [resource("r")],
    None,
  )
  try
    @scheduling.validate_schedule(valid, [
      slot("a", "r", 0, 2),
      slot("a", "r", 2, 4),
    ])
  catch {
    @scheduling.SchedulingError::InvalidSchedule(message) =>
      inspect(message, content="duplicate scheduled task: a")
    _ => fail("wrong duplicate schedule error")
  } noraise {
    _ => fail("expected duplicate schedule error")
  }
}
