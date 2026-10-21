///|
test "pipeline adapter compares shared scheduler results and runner load" {
  let analysis = try! @pipeline.analyze_pipeline(
    stages=[
      {
        id: "compile",
        duration: 8,
        runner: "runner-a",
        priority: 2,
        prerequisites: [],
      },
      {
        id: "lint",
        duration: 4,
        runner: "runner-b",
        priority: 1,
        prerequisites: [],
      },
      {
        id: "test",
        duration: 5,
        runner: "runner-a",
        priority: 3,
        prerequisites: ["compile"],
      },
    ],
    runners=["runner-a", "runner-b"],
    target_makespan=Some(12),
    search_budget=10,
  )
  assert_eq(analysis.baselines.length(), 3)
  for baseline in analysis.baselines {
    try! @scheduling.validate_schedule(analysis.problem, baseline.schedule)
    assert_eq(baseline.makespan, 13)
  }
  try! @scheduling.validate_schedule(
    analysis.problem,
    analysis.optimization.result.schedule,
  )
  assert_eq(analysis.optimization.result.makespan, 13)
  assert_eq(analysis.bottleneck_runner, Some("runner-a"))
  assert_eq(analysis.bottleneck_load, 13)
  assert_eq(analysis.target_met, Some(false))
}

///|
test "pipeline adapter rejects missing runner through generic validation" {
  try
    @pipeline.analyze_pipeline(
      stages=[
        {
          id: "compile",
          duration: 2,
          runner: "missing",
          priority: 0,
          prerequisites: [],
        },
      ],
      runners=["runner-a"],
      target_makespan=None,
      search_budget=0,
    )
  catch {
    @scheduling.SchedulingError::InvalidResource(_) => ()
    _ => fail("wrong missing runner error")
  } noraise {
    _ => fail("expected missing runner error")
  }
}
