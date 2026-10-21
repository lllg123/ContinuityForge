///|
fn ranked_task(
  id : String,
  duration : Int,
  priority : Int,
  resource : String,
) -> @scheduling.Task {
  try! @scheduling.Task::new(id~, duration~, priority~, resource_id=resource)
}

///|
test "all baselines use the same problem and return feasible results" {
  let p = problem(
    [
      ranked_task("restore-worker", 15, 1, "compute"),
      ranked_task("restore-api", 20, 2, "compute"),
      ranked_task("restore-db", 10, 3, "database"),
      ranked_task("restore-router", 25, 0, "network"),
    ],
    [edge("restore-api", "restore-db")],
    [resource("database"), resource("compute"), resource("network")],
    Some(70),
  )
  for
    baseline in [
      @scheduling.Baseline::StableTopological,
      @scheduling.Baseline::RecoveryHeuristic,
      @scheduling.Baseline::CriticalPath,
    ] {
    let result = try! @scheduling.run_baseline(p, baseline)
    try! @scheduling.validate_schedule(p, result.schedule)
    assert_eq(result.schedule.length(), p.tasks.length())
    assert_true(result.makespan <= 70)
  }
  let legacy_rule = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::RecoveryHeuristic,
  )
  assert_eq(legacy_rule.schedule.map(entry => entry.task_id), [
    "restore-db", "restore-api", "restore-worker", "restore-router",
  ])
  assert_eq(legacy_rule.schedule.map(entry => entry.start), [0, 10, 30, 0])
  assert_eq(legacy_rule.makespan, 45)
}

///|
test "stable topology follows FIFO ready order and fills earlier gaps" {
  let p = problem(
    [
      task("gateway", 2, "database"),
      task("router", 2, "compute"),
      task("api", 2, "compute"),
      task("database", 2, "database"),
    ],
    [edge("api", "database"), edge("gateway", "router")],
    [resource("database"), resource("compute")],
    None,
  )
  let result = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::StableTopological,
  )
  assert_eq(result.schedule.map(entry => entry.task_id), [
    "router", "database", "gateway", "api",
  ])
  assert_eq(result.makespan, 4)
  assert_eq(result.explanation.algorithm, "stable-topological")
}

///|
test "recovery heuristic raises a low rank prerequisite for its dependent" {
  let p = problem(
    [
      ranked_task("unrelated", 6, 2, "shared"),
      ranked_task("prerequisite", 2, 0, "shared"),
      ranked_task("critical", 3, 3, "other"),
    ],
    [edge("critical", "prerequisite")],
    [resource("shared"), resource("other")],
    None,
  )
  let topo = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::StableTopological,
  )
  let recovery = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::RecoveryHeuristic,
  )
  assert_eq(topo.makespan, 11)
  assert_eq(recovery.makespan, 8)
  assert_eq(recovery.schedule[0].task_id, "prerequisite")
  assert_eq(recovery.schedule[1].task_id, "critical")
  assert_eq(recovery.explanation.algorithm, "recovery-heuristic")
}

///|
test "critical path favors the longer remaining chain" {
  let p = problem(
    [
      task("unrelated", 6, "shared"),
      task("prerequisite", 2, "shared"),
      task("dependent", 8, "other"),
    ],
    [edge("dependent", "prerequisite")],
    [resource("shared"), resource("other")],
    None,
  )
  let topo = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::StableTopological,
  )
  let critical = try! @scheduling.run_baseline(
    p,
    @scheduling.Baseline::CriticalPath,
  )
  assert_eq(topo.makespan, 16)
  assert_eq(critical.makespan, 10)
  assert_eq(critical.schedule[0].task_id, "prerequisite")
  assert_eq(critical.explanation.algorithm, "critical-path")
}

///|
test "all baselines handle empty problems and enforce a target" {
  let empty = problem([], [], [], Some(0))
  for
    baseline in [
      @scheduling.Baseline::StableTopological,
      @scheduling.Baseline::RecoveryHeuristic,
      @scheduling.Baseline::CriticalPath,
    ] {
    let result = try! @scheduling.run_baseline(empty, baseline)
    assert_eq(result.makespan, 0)
  }
  let p = problem([task("a", 5, "r")], [], [resource("r")], Some(4))
  try
    @scheduling.run_baseline(p, @scheduling.Baseline::StableTopological)
  catch {
    @scheduling.SchedulingError::InvalidSchedule(message) =>
      inspect(message, content="makespan 5 exceeds target 4")
    _ => fail("wrong target error")
  } noraise {
    _ => fail("expected unmet target")
  }
}

///|
test "baseline rejects arithmetic overflow instead of wrapping time" {
  let p = problem(
    [task("a", 2147483647, "r"), task("b", 1, "r")],
    [],
    [resource("r")],
    None,
  )
  try
    @scheduling.run_baseline(p, @scheduling.Baseline::StableTopological)
  catch {
    @scheduling.SchedulingError::InvalidSchedule(message) =>
      inspect(message, content="schedule exceeds integer time range")
    _ => fail("wrong overflow error")
  } noraise {
    _ => fail("expected overflow error")
  }
}
