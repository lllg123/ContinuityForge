///|
fn minutes(amount : Int) -> @continuity_forge.TimeSpan {
  try! @continuity_forge.TimeSpan::new(
    amount~,
    unit=@continuity_forge.TimeUnit::Minutes,
  )
}

///|
test "recovery adapter preserves incident paths and uses generic scheduler" {
  let database = @continuity_forge.AssetRef::Component(
    try! @continuity_forge.ComponentId::new(value="db"),
  )
  let api = @continuity_forge.AssetRef::Service(
    try! @continuity_forge.ServiceId::new(value="api"),
  )
  let worker = @continuity_forge.AssetRef::Service(
    try! @continuity_forge.ServiceId::new(value="worker"),
  )
  let items = [
    try! @continuity_forge.RecoveryItem::new(
      asset=worker,
      impact_level=@continuity_forge.ImpactLevel::Medium,
      recovery_time=minutes(15),
      resource="compute",
    ),
    try! @continuity_forge.RecoveryItem::new(
      asset=api,
      impact_level=@continuity_forge.ImpactLevel::High,
      recovery_time=minutes(20),
      resource="compute",
    ),
    try! @continuity_forge.RecoveryItem::new(
      asset=database,
      impact_level=@continuity_forge.ImpactLevel::Critical,
      recovery_time=minutes(10),
      resource="database",
    ),
  ]
  let dependencies = [
    try! @continuity_forge.Dependency::new(dependent=api, dependency=database),
  ]
  let constraints = try! @continuity_forge.RecoveryConstraints::new(
    target_window=minutes(40),
    available_resources=["database", "compute"],
  )
  let analysis = try! @recovery.analyze_recovery(
    failed_asset=database,
    assets=[database, api, worker],
    dependencies~,
    items~,
    constraints~,
    search_budget=10,
  )
  assert_eq(analysis.incident.affected.length(), 1)
  assert_eq(analysis.incident.paths[0].path.length(), 2)
  assert_eq(analysis.problem.tasks.length(), 3)
  try! @scheduling.validate_schedule(
    analysis.problem,
    analysis.optimization.result.schedule,
  )
  assert_eq(analysis.optimization.result.makespan, 35)
  assert_true(analysis.target_met)
  assert_eq(analysis.target_window_minutes, 40)
  let old = try! @continuity_forge.plan_recovery(
    items~,
    dependencies~,
    constraints=try! @continuity_forge.RecoveryConstraints::new(
      target_window=minutes(45),
      available_resources=["database", "compute"],
    ),
  )
  assert_eq(old.total_time_minutes, 45)
}

///|
test "recovery adapter reports impossible target without hiding the schedule" {
  let service = @continuity_forge.AssetRef::Service(
    try! @continuity_forge.ServiceId::new(value="only"),
  )
  let analysis = try! @recovery.analyze_recovery(
    failed_asset=service,
    assets=[service],
    dependencies=[],
    items=[
      try! @continuity_forge.RecoveryItem::new(
        asset=service,
        impact_level=@continuity_forge.ImpactLevel::High,
        recovery_time=minutes(10),
        resource="team",
      ),
    ],
    constraints=try! @continuity_forge.RecoveryConstraints::new(
      target_window=minutes(5),
      available_resources=["team"],
    ),
    search_budget=0,
  )
  assert_true(!analysis.target_met)
  assert_eq(analysis.optimization.result.makespan, 10)
}
