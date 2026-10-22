///|
test "bounded search improves a baseline local-order trap" {
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
  let report = try! @scheduling.optimize_schedule(p, 10)
  assert_eq(report.best_baseline_makespan, 19)
  assert_eq(report.initial_makespan, 19)
  assert_eq(report.lower_bound, 11)
  assert_eq(report.result.makespan, 12)
  assert_true(report.candidates_evaluated <= 10)
  assert_true(report.accepted_moves > 0)
  try! @scheduling.validate_schedule(p, report.result.schedule)
}

///|
test "zero budget returns a feasible seed without local moves" {
  let p = problem(
    [task("a", 2, "r"), task("b", 3, "r")],
    [],
    [resource("r")],
    None,
  )
  let report = try! @scheduling.optimize_schedule(p, 0)
  assert_eq(report.result.makespan, 5)
  assert_eq(report.candidates_evaluated, 0)
  assert_eq(report.accepted_moves, 0)
  assert_eq(report.result.explanation.algorithm, "stable-topological")
}

///|
test "ablation switches isolate seed features and local search" {
  let p = problem(
    [
      ranked_task("a", 10, 3, "shared"),
      ranked_task("b", 1, 0, "shared"),
      ranked_task("c", 1, 3, "runner-c"),
      ranked_task("d", 8, 0, "runner-d"),
    ],
    [edge("c", "a"), edge("d", "b")],
    [resource("shared"), resource("runner-c"), resource("runner-d")],
    None,
  )
  let full = try! @scheduling.optimize_schedule(p, 10)
  let switched = try! @scheduling.optimize_schedule_with_features(
    p, 10, true, true, true,
  )
  assert_eq(full.result.makespan, switched.result.makespan)
  let no_search = try! @scheduling.optimize_schedule_with_features(
    p, 10, true, true, false,
  )
  assert_eq(no_search.candidates_evaluated, 0)
  assert_eq(no_search.accepted_moves, 0)
  for
    (critical, load, search) in [
      (false, true, true),
      (true, false, true),
      (true, true, false),
    ] {
    let report = try! @scheduling.optimize_schedule_with_features(
      p, 10, critical, load, search,
    )
    try! @scheduling.validate_schedule(p, report.result.schedule)
  }
}

///|
test "negative search budget is rejected" {
  let p = problem([], [], [], None)
  try @scheduling.optimize_schedule(p, -1) catch {
    @scheduling.SchedulingError::InvalidConstraint(message) =>
      inspect(message, content="search budget cannot be negative")
    _ => fail("wrong budget error")
  } noraise {
    _ => fail("expected budget error")
  }
}
