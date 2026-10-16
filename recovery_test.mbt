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
      resource="compute",
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
        content="target 60m is below unavoidable lower bound 80m (dependency 40m, resource 80m)",
      )
    _ => fail("wrong error for recovery target")
  } noraise {
    _ => fail("expected an unmet recovery target")
  }
}

///|
test "different teams overlap while one team queues its work" {
  let database = try! recovery_component(value="postgres-primary")
  let api = try! recovery_service(value="checkout-api")
  let worker = try! recovery_service(value="checkout-worker")
  let network = try! recovery_component(value="edge-router")
  let plan = try! @continuity_forge.prioritize_recovery(
    items=[
      try! recovery_item(
        asset=worker,
        impact_level=@continuity_forge.ImpactLevel::Medium,
        minutes=15,
        resource="compute",
      ),
      try! recovery_item(
        asset=network,
        impact_level=@continuity_forge.ImpactLevel::Low,
        minutes=25,
        resource="network",
      ),
      try! recovery_item(
        asset=api,
        impact_level=@continuity_forge.ImpactLevel::High,
        minutes=20,
        resource="compute",
      ),
      try! recovery_item(
        asset=database,
        impact_level=@continuity_forge.ImpactLevel::Critical,
        minutes=10,
        resource="database",
      ),
    ],
    dependencies=[try! recovery_edge(dependent=api, dependency=database)],
    constraints=try! @continuity_forge.RecoveryConstraints::new(
      target_window=try! @continuity_forge.TimeSpan::new(
        amount=45,
        unit=@continuity_forge.TimeUnit::Minutes,
      ),
      available_resources=["database", "compute", "network"],
    ),
  )
  assert_eq(plan.ordered.map(recovery_key), [
    "component:postgres-primary", "service:checkout-api", "service:checkout-worker",
    "component:edge-router",
  ])
  assert_eq(plan.schedule.map(entry => entry.start_minutes), [0, 10, 30, 0])
  assert_eq(plan.schedule.map(entry => entry.end_minutes), [10, 30, 45, 25])
  assert_eq(plan.total_time_minutes, 45)
  assert_eq(plan.dependency_lower_bound_minutes, 30)
  assert_eq(plan.resource_lower_bound_minutes, 35)
  assert_eq(plan.slack_minutes, 0)
}

///|
test "a critical dependent raises its prerequisite priority" {
  let database = try! recovery_component(value="postgres-primary")
  let api = try! recovery_service(value="checkout-api")
  let worker = try! recovery_service(value="checkout-worker")
  let plan = try! @continuity_forge.prioritize_recovery(
    items=[
      try! recovery_item(
        asset=worker,
        impact_level=@continuity_forge.ImpactLevel::High,
        minutes=15,
        resource="compute",
      ),
      try! recovery_item(
        asset=api,
        impact_level=@continuity_forge.ImpactLevel::Critical,
        minutes=20,
        resource="network",
      ),
      try! recovery_item(
        asset=database,
        impact_level=@continuity_forge.ImpactLevel::Low,
        minutes=10,
        resource="compute",
      ),
    ],
    dependencies=[try! recovery_edge(dependent=api, dependency=database)],
    constraints=try! @continuity_forge.RecoveryConstraints::new(
      target_window=try! @continuity_forge.TimeSpan::new(
        amount=30,
        unit=@continuity_forge.TimeUnit::Minutes,
      ),
      available_resources=["compute", "network"],
    ),
  )
  assert_eq(plan.ordered.map(recovery_key), [
    "component:postgres-primary", "service:checkout-api", "service:checkout-worker",
  ])
  assert_eq(plan.schedule.map(entry => entry.start_minutes), [0, 10, 10])
  assert_eq(plan.total_time_minutes, 30)
}

///|
test "independent resources satisfy a window shorter than the work sum" {
  let api = try! recovery_service(value="checkout-api")
  let database = try! recovery_component(value="postgres-primary")
  let plan = try! @continuity_forge.prioritize_recovery(
    items=[
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
    ],
    dependencies=[],
    constraints=try! recovery_constraints(target_minutes=40),
  )
  assert_eq(plan.schedule.map(entry => entry.start_minutes), [0, 0])
  assert_eq(plan.total_time_minutes, 40)
  assert_eq(plan.slack_minutes, 0)
}

///|
test "resource serialization proves an impossible window" {
  let api = try! recovery_service(value="checkout-api")
  let worker = try! recovery_service(value="checkout-worker")
  try
    @continuity_forge.prioritize_recovery(
      items=[
        try! recovery_item(
          asset=api,
          impact_level=@continuity_forge.ImpactLevel::High,
          minutes=40,
          resource="compute",
        ),
        try! recovery_item(
          asset=worker,
          impact_level=@continuity_forge.ImpactLevel::Medium,
          minutes=40,
          resource="compute",
        ),
      ],
      dependencies=[],
      constraints=try! recovery_constraints(target_minutes=60),
    )
  catch {
    @continuity_forge.ModelError::RecoveryTargetUnmet(message) =>
      inspect(
        message,
        content="target 60m is below unavoidable lower bound 80m (dependency 40m, resource 80m)",
      )
    _ => fail("wrong error for resource lower bound")
  } noraise {
    _ => fail("expected an impossible recovery window")
  }
}

///|
test "later selected work can fill an earlier resource gap" {
  let database = try! recovery_component(value="database")
  let api = try! recovery_service(value="api")
  let router = try! recovery_component(value="router")
  let gateway = try! recovery_service(value="gateway")
  let plan = try! @continuity_forge.prioritize_recovery(
    items=[
      try! recovery_item(
        asset=gateway,
        impact_level=@continuity_forge.ImpactLevel::High,
        minutes=2,
        resource="database",
      ),
      try! recovery_item(
        asset=router,
        impact_level=@continuity_forge.ImpactLevel::High,
        minutes=2,
        resource="compute",
      ),
      try! recovery_item(
        asset=api,
        impact_level=@continuity_forge.ImpactLevel::Critical,
        minutes=2,
        resource="compute",
      ),
      try! recovery_item(
        asset=database,
        impact_level=@continuity_forge.ImpactLevel::Critical,
        minutes=2,
        resource="database",
      ),
    ],
    dependencies=[
      try! recovery_edge(dependent=api, dependency=database),
      try! recovery_edge(dependent=gateway, dependency=router),
    ],
    constraints=try! recovery_constraints(target_minutes=4),
  )
  assert_eq(plan.ordered.map(recovery_key), [
    "component:database", "service:api", "component:router", "service:gateway",
  ])
  assert_eq(plan.schedule.map(entry => entry.start_minutes), [0, 2, 0, 2])
  assert_eq(plan.schedule.map(entry => entry.end_minutes), [2, 4, 2, 4])
  assert_eq(plan.total_time_minutes, 4)
  assert_eq(plan.dependency_lower_bound_minutes, 4)
  assert_eq(plan.resource_lower_bound_minutes, 4)
}
