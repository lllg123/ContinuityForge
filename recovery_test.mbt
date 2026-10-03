///|
fn recovery_service(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(@continuity_forge.ServiceId::new(value~))
}

///|
fn recovery_component(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Component(
    @continuity_forge.ComponentId::new(value~),
  )
}

///|
fn recovery_item(
  asset~ : @continuity_forge.AssetRef,
  impact_level~ : @continuity_forge.ImpactLevel,
  minutes~ : Int,
  resource~ : String,
) -> @continuity_forge.RecoveryItem raise @continuity_forge.ModelError {
  @continuity_forge.RecoveryItem::new(
    asset~,
    impact_level~,
    recovery_time=try! @continuity_forge.TimeSpan::new(
      amount=minutes,
      unit=@continuity_forge.TimeUnit::Minutes,
    ),
    resource~,
  )
}

///|
fn recovery_key(item : @continuity_forge.RecoveryItem) -> String {
  match item.asset {
    @continuity_forge.AssetRef::Service(id) => "service:\{id.value}"
    @continuity_forge.AssetRef::Component(id) => "component:\{id.value}"
  }
}

///|
fn recovery_edge(
  dependent~ : @continuity_forge.AssetRef,
  dependency~ : @continuity_forge.AssetRef,
) -> @continuity_forge.Dependency raise @continuity_forge.ModelError {
  @continuity_forge.Dependency::new(dependent~, dependency~)
}

///|
fn recovery_constraints(
  target_minutes~ : Int,
) -> @continuity_forge.RecoveryConstraints raise @continuity_forge.ModelError {
  @continuity_forge.RecoveryConstraints::new(
    target_window=try! @continuity_forge.TimeSpan::new(
      amount=target_minutes,
      unit=@continuity_forge.TimeUnit::Minutes,
    ),
    available_resources=["database", "compute"],
  )
}

///|
test "prerequisites are recovered before higher priority dependents" {
  let database = try! recovery_component(value="postgres-primary")
  let api = try! recovery_service(value="checkout-api")
  let checkout = try! recovery_service(value="checkout")
  let items = [
    try! recovery_item(
      asset=checkout,
      impact_level=@continuity_forge.ImpactLevel::Critical,
      minutes=20,
      resource="compute",
    ),
    try! recovery_item(
      asset=api,
      impact_level=@continuity_forge.ImpactLevel::High,
      minutes=20,
      resource="compute",
    ),
    try! recovery_item(
      asset=database,
      impact_level=@continuity_forge.ImpactLevel::Low,
      minutes=10,
      resource="database",
    ),
  ]
  let plan = try! @continuity_forge.prioritize_recovery(
    items~,
    dependencies=[
      try! recovery_edge(dependent=api, dependency=database),
      try! recovery_edge(dependent=checkout, dependency=api),
    ],
    constraints=try! recovery_constraints(target_minutes=60),
  )
  assert_eq(plan.ordered.map(recovery_key), [
    "component:postgres-primary", "service:checkout-api", "service:checkout",
  ])
  assert_eq(plan.total_time_minutes, 50)
}

///|
test "ready assets are prioritized by impact then duration" {
  let api = try! recovery_service(value="checkout-api")
  let worker = try! recovery_service(value="checkout-worker")
  let database = try! recovery_component(value="postgres-primary")
  let plan = try! @continuity_forge.prioritize_recovery(
    items=[
      try! recovery_item(
        asset=api,
        impact_level=@continuity_forge.ImpactLevel::Medium,
        minutes=30,
        resource="compute",
      ),
      try! recovery_item(
        asset=worker,
        impact_level=@continuity_forge.ImpactLevel::Critical,
        minutes=40,
        resource="compute",
      ),
      try! recovery_item(
        asset=database,
        impact_level=@continuity_forge.ImpactLevel::Critical,
        minutes=10,
        resource="database",
      ),
    ],
    dependencies=[],
    constraints=try! recovery_constraints(target_minutes=120),
  )
  assert_eq(plan.ordered.map(recovery_key), [
    "component:postgres-primary", "service:checkout-worker", "service:checkout-api",
  ])
}

///|
test "unavailable resources produce a clear conflict" {
  let api = try! recovery_service(value="checkout-api")
  let item = try! recovery_item(
    asset=api,
    impact_level=@continuity_forge.ImpactLevel::High,
    minutes=20,
    resource="network",
  )
  let constraints = try! @continuity_forge.RecoveryConstraints::new(
    target_window=try! @continuity_forge.TimeSpan::new(
      amount=60,
      unit=@continuity_forge.TimeUnit::Minutes,
    ),
    available_resources=["compute"],
  )
  try
    @continuity_forge.prioritize_recovery(
      items=[item],
      dependencies=[],
      constraints~,
    )
  catch {
    @continuity_forge.ModelError::RecoveryResourceConflict(message) =>
      inspect(
        message,
        content="resource unavailable for service:checkout-api: network",
      )
    _ => fail("wrong error for unavailable resource")
  } noraise {
    _ => fail("expected a resource conflict")
  }
}

///|
test "recovery windows that cannot fit are rejected" {
  let api = try! recovery_service(value="checkout-api")
  let database = try! recovery_component(value="postgres-primary")
  let items = [
    try! recovery_item(
      asset=api,
      impact_level=@continuity_forge.ImpactLevel::High,
      minutes=40,
      resource="compute",
    ),
    try! recovery_item(
      asset=database,
      impact_level=@continuity_forge.ImpactLevel::Medium,
      minutes=40,
      resource="database",
    ),
  ]
  try
    @continuity_forge.prioritize_recovery(
      items~,
      dependencies=[],
      constraints=try! recovery_constraints(target_minutes=60),
    )
  catch {
    @continuity_forge.ModelError::RecoveryTargetUnmet(message) =>
      inspect(
        message,
        content="recovery window exceeded at component:postgres-primary",
      )
    _ => fail("wrong error for recovery target")
  } noraise {
    _ => fail("expected an unmet recovery target")
  }
}
