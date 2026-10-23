///|
fn rcpsp_example() -> @scheduling.RcpspProblem {
  try! @scheduling.RcpspProblem::new(
    tasks=[
      try! @scheduling.RcpspTask::new(
        id="a",
        duration=3,
        priority=0,
        demands=[
          try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=2),
          try! @scheduling.ResourceDemand::new(resource_id="memory", amount=2),
        ],
        release_time=2,
        deadline=Some(5),
      ),
      try! @scheduling.RcpspTask::new(
        id="b",
        duration=3,
        priority=0,
        demands=[
          try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=1),
        ],
        release_time=2,
        deadline=None,
      ),
      try! @scheduling.RcpspTask::new(
        id="c",
        duration=2,
        priority=0,
        demands=[
          try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=3),
          try! @scheduling.ResourceDemand::new(resource_id="memory", amount=1),
        ],
        release_time=0,
        deadline=Some(7),
      ),
    ],
    dependencies=[
      try! @scheduling.Dependency::new(task_id="c", prerequisite_id="a"),
    ],
    resources=[
      try! @scheduling.RenewableResource::new(id="cpu", capacity=4),
      try! @scheduling.RenewableResource::new(id="memory", capacity=3),
    ],
    target_makespan=Some(7),
  )
}

///|
fn rcpsp_entry(
  id : String,
  start : Int,
  finish : Int,
) -> @scheduling.RcpspScheduleEntry {
  try! @scheduling.RcpspScheduleEntry::new(task_id=id, start~, finish~)
}

///|
fn has_violation(
  issues : Array[@scheduling.ConstraintViolation],
  kind : String,
) -> Bool {
  for issue in issues {
    if issue.kind == kind {
      return true
    }
  }
  false
}

///|
test "renewable capacity and multi-resource tasks obey half-open intervals" {
  let p = rcpsp_example()
  let valid = [
    rcpsp_entry("a", 2, 5),
    rcpsp_entry("b", 2, 5),
    rcpsp_entry("c", 5, 7),
  ]
  try! @scheduling.validate_rcpsp_schedule(p, valid)
  let overloaded = [
    rcpsp_entry("a", 2, 5),
    rcpsp_entry("b", 2, 5),
    rcpsp_entry("c", 3, 5),
  ]
  let issues = @scheduling.inspect_rcpsp_schedule(p, overloaded)
  assert_true(has_violation(issues, "capacity"))
  assert_true(has_violation(issues, "precedence"))
  let memory_only = [
    rcpsp_entry("a", 2, 5),
    rcpsp_entry("b", 2, 5),
    rcpsp_entry("c", 5, 7),
  ]
  try! @scheduling.validate_rcpsp_schedule(p, memory_only)
}

///|
test "a second resource can reject a schedule even when CPU fits" {
  let p = try! @scheduling.RcpspProblem::new(
    tasks=[
      try! @scheduling.RcpspTask::new(
        id="a",
        duration=3,
        priority=0,
        demands=[
          try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=2),
          try! @scheduling.ResourceDemand::new(resource_id="memory", amount=2),
        ],
        release_time=0,
        deadline=None,
      ),
      try! @scheduling.RcpspTask::new(
        id="b",
        duration=3,
        priority=0,
        demands=[
          try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=2),
          try! @scheduling.ResourceDemand::new(resource_id="memory", amount=2),
        ],
        release_time=0,
        deadline=None,
      ),
    ],
    dependencies=[],
    resources=[
      try! @scheduling.RenewableResource::new(id="cpu", capacity=4),
      try! @scheduling.RenewableResource::new(id="memory", capacity=3),
    ],
    target_makespan=None,
  )
  let issues = @scheduling.inspect_rcpsp_schedule(p, [
    rcpsp_entry("a", 0, 3),
    rcpsp_entry("b", 0, 3),
  ])
  assert_true(has_violation(issues, "capacity"))
  assert_eq(issues[0].resource_id, Some("memory"))
  try! @scheduling.validate_rcpsp_schedule(p, [
    rcpsp_entry("a", 0, 3),
    rcpsp_entry("b", 3, 6),
  ])
}

///|
test "release deadline target and completeness violations are structured" {
  let p = rcpsp_example()
  let early = [
    rcpsp_entry("a", 1, 4),
    rcpsp_entry("b", 2, 5),
    rcpsp_entry("c", 5, 7),
  ]
  assert_true(
    has_violation(@scheduling.inspect_rcpsp_schedule(p, early), "release_time"),
  )
  let late = [
    rcpsp_entry("a", 3, 6),
    rcpsp_entry("b", 2, 5),
    rcpsp_entry("c", 6, 8),
  ]
  let issues = @scheduling.inspect_rcpsp_schedule(p, late)
  assert_true(has_violation(issues, "deadline"))
  assert_true(has_violation(issues, "target"))
  assert_true(
    has_violation(
      @scheduling.inspect_rcpsp_schedule(p, [rcpsp_entry("a", 2, 5)]),
      "completeness",
    ),
  )
}

///|
test "invalid demand and time overflow reject mutable public inputs" {
  let p = rcpsp_example()
  p.tasks[0].demands[0] = { resource_id: "cpu", amount: 5, }
  assert_true(has_violation(@scheduling.inspect_rcpsp_problem(p), "demand"))
  let p2 = rcpsp_example()
  p2.tasks[0] = {
    id: "a",
    duration: 3,
    priority: 0,
    demands: p2.tasks[0].demands,
    release_time: 2147483647,
    deadline: None,
  }
  assert_true(
    has_violation(@scheduling.inspect_rcpsp_problem(p2), "time_range"),
  )
}

///|
test "legacy exclusive resource maps to capacity one without changing old API" {
  let legacy = try! @scheduling.SchedulingProblem::new(
    tasks=[
      try! @scheduling.Task::new(
        id="old",
        duration=3,
        priority=1,
        resource_id="runner",
      ),
    ],
    dependencies=[],
    constraints=try! @scheduling.Constraints::new(
      resources=[try! @scheduling.Resource::new(id="runner")],
      target_makespan=Some(3),
    ),
  )
  let upgraded = try! @scheduling.upgrade_exclusive_problem(legacy)
  assert_eq(upgraded.resources[0].capacity, 1)
  assert_eq(upgraded.tasks[0].demands[0].amount, 1)
  try! @scheduling.validate_rcpsp_schedule(upgraded, [rcpsp_entry("old", 0, 3)])
}

///|
test "zero-duration empty milestone is legal" {
  let p = try! @scheduling.RcpspProblem::new(
    tasks=[
      try! @scheduling.RcpspTask::new(
        id="start",
        duration=0,
        priority=0,
        demands=[],
        release_time=0,
        deadline=Some(0),
      ),
    ],
    dependencies=[],
    resources=[],
    target_makespan=Some(0),
  )
  try! @scheduling.validate_rcpsp_schedule(p, [rcpsp_entry("start", 0, 0)])
}

///|
test "all RCPSP policies decode multi-resource intervals and validate them" {
  let problem = rcpsp_example()
  for
    algorithm in [
      @scheduling.RcpspAlgorithm::StableTopological,
      @scheduling.RcpspAlgorithm::CriticalPath,
      @scheduling.RcpspAlgorithm::RecoveryHeuristic,
    ] {
    let result = try! @scheduling.solve_rcpsp(problem, algorithm)
    assert_eq(result.status, "FEASIBLE")
    assert_eq(result.makespan, Some(7))
    assert_eq(result.candidates_evaluated, 1)
    try! @scheduling.validate_rcpsp_schedule(problem, result.schedule)
  }
}

///|
test "budgeted search is deterministic and rejects an impossible target" {
  let problem = rcpsp_example()
  let first = try! @scheduling.optimize_rcpsp(problem, 5)
  let second = try! @scheduling.optimize_rcpsp(problem, 5)
  assert_eq(first.status, "FEASIBLE")
  assert_eq(first.makespan, second.makespan)
  assert_eq(first.candidates_evaluated, second.candidates_evaluated)
  assert_true(first.candidates_evaluated >= 3)
  assert_eq(first.budget, 5)
  for i, entry in first.schedule {
    assert_eq(entry.task_id, second.schedule[i].task_id)
    assert_eq(entry.start, second.schedule[i].start)
  }
  try! @scheduling.validate_rcpsp_schedule(problem, first.schedule)
  let impossible = try! @scheduling.RcpspProblem::new(
    tasks=problem.tasks,
    dependencies=problem.dependencies,
    resources=problem.resources,
    target_makespan=Some(6),
  )
  let result = try! @scheduling.optimize_rcpsp(impossible, 5)
  assert_eq(result.status, "UNKNOWN")
  assert_eq(result.makespan, None)
}

///|
test "parallel capacity reduces makespan and hard release is respected" {
  let tasks = [
    try! @scheduling.RcpspTask::new(
      id="first",
      duration=3,
      priority=0,
      demands=[
        try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=2),
      ],
      release_time=0,
      deadline=None,
    ),
    try! @scheduling.RcpspTask::new(
      id="second",
      duration=3,
      priority=0,
      demands=[
        try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=2),
      ],
      release_time=2,
      deadline=Some(5),
    ),
  ]
  let parallel = try! @scheduling.RcpspProblem::new(
    tasks~,
    dependencies=[],
    resources=[try! @scheduling.RenewableResource::new(id="cpu", capacity=4)],
    target_makespan=Some(5),
  )
  let parallel_result = try! @scheduling.solve_rcpsp(
    parallel,
    @scheduling.RcpspAlgorithm::StableTopological,
  )
  assert_eq(parallel_result.makespan, Some(5))
  try! @scheduling.validate_rcpsp_schedule(parallel, parallel_result.schedule)
  let serial_tasks = [
    tasks[0],
    try! @scheduling.RcpspTask::new(
      id="second",
      duration=3,
      priority=0,
      demands=[
        try! @scheduling.ResourceDemand::new(resource_id="cpu", amount=2),
      ],
      release_time=2,
      deadline=None,
    ),
  ]
  let serial = try! @scheduling.RcpspProblem::new(
    tasks=serial_tasks,
    dependencies=[],
    resources=[try! @scheduling.RenewableResource::new(id="cpu", capacity=2)],
    target_makespan=None,
  )
  let serial_result = try! @scheduling.solve_rcpsp(
    serial,
    @scheduling.RcpspAlgorithm::StableTopological,
  )
  assert_eq(serial_result.makespan, Some(6))
  try! @scheduling.validate_rcpsp_schedule(serial, serial_result.schedule)
}
