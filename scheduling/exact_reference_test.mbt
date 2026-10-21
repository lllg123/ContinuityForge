///|
test "exact search proves the local-search example optimum" {
  let p = problem(
    [
      ranked_task("a", 10, 3, "shared"),
      ranked_task("b", 1, 0, "shared"),
      ranked_task("c", 1, 3, "runner-c"),
      ranked_task("d", 8, 0, "runner-d"),
    ],
    [edge("c", "a"), edge("d", "b")],
    [resource("shared"), resource("runner-c"), resource("runner-d")],
    Some(12),
  )
  let reference = try! @scheduling.exact_reference(p, 1000)
  assert_true(reference.proven_optimal)
  let optimum = match reference.best {
    Some(value) => value
    None => fail("complete search must have a result")
  }
  assert_eq(optimum.makespan, 12)
  try! @scheduling.validate_schedule(p, optimum.schedule)
  let relaxed = problem(p.tasks, p.dependencies, p.constraints.resources, None)
  for
    baseline in [
      @scheduling.Baseline::StableTopological,
      @scheduling.Baseline::RecoveryHeuristic,
      @scheduling.Baseline::CriticalPath,
    ] {
    let candidate = try! @scheduling.run_baseline(relaxed, baseline)
    assert_true(candidate.makespan >= optimum.makespan)
    let gap = try! @scheduling.optimality_gap_percent(candidate, reference)
    assert_true(gap > 58.0 && gap < 59.0)
  }
  let improved = try! @scheduling.optimize_schedule(p, 10)
  assert_eq(
    try! @scheduling.optimality_gap_percent(improved.result, reference),
    0.0,
  )
}

///|
test "incomplete search never claims an optimum" {
  let p = problem(
    [task("a", 2, "r"), task("b", 3, "r")],
    [],
    [resource("r")],
    None,
  )
  let reference = try! @scheduling.exact_reference(p, 2)
  assert_true(!reference.proven_optimal)
  assert_eq(reference.explored_nodes, 2)
  let candidate = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::StableTopological,
  )
  try @scheduling.optimality_gap_percent(candidate, reference) catch {
    @scheduling.SchedulingError::InvalidConstraint(message) =>
      inspect(message, content="exact reference is incomplete")
    _ => fail("wrong incomplete search error")
  } noraise {
    _ => fail("expected incomplete search error")
  }
}

///|
test "empty and single-task problems have exact references" {
  let empty = problem([], [], [], Some(0))
  let empty_reference = try! @scheduling.exact_reference(empty, 1)
  assert_true(empty_reference.proven_optimal)
  let empty_best = match empty_reference.best {
    Some(value) => value
    None => fail("empty optimum missing")
  }
  assert_eq(empty_best.makespan, 0)
  let single = problem([task("only", 7, "r")], [], [resource("r")], None)
  let single_reference = try! @scheduling.exact_reference(single, 2)
  assert_true(single_reference.proven_optimal)
  let single_best = match single_reference.best {
    Some(value) => value
    None => fail("single optimum missing")
  }
  assert_eq(single_best.makespan, 7)
}

///|
test "exact solver rejects unsupported size and invalid budget" {
  let p = problem([], [], [], None)
  try @scheduling.exact_reference(p, 0) catch {
    @scheduling.SchedulingError::InvalidConstraint(_) => ()
    _ => fail("wrong budget error")
  } noraise {
    _ => fail("expected budget error")
  }
  let tasks : Array[@scheduling.Task] = []
  for i in 0..<9 {
    tasks.push(task("task-\{i}", 1, "r"))
  }
  let large = problem(tasks, [], [resource("r")], None)
  try @scheduling.exact_reference(large, 100000) catch {
    @scheduling.SchedulingError::InvalidConstraint(message) =>
      inspect(message, content="exact reference supports at most 8 tasks")
    _ => fail("wrong size error")
  } noraise {
    _ => fail("expected size error")
  }
}
