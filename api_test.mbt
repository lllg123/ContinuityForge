///|
fn api_service_id(
  value~ : String,
) -> @continuity_forge.ServiceId raise @continuity_forge.ModelError {
  @continuity_forge.ServiceId::new(value~)
}

///|
fn api_component_id(
  value~ : String,
) -> @continuity_forge.ComponentId raise @continuity_forge.ModelError {
  @continuity_forge.ComponentId::new(value~)
}

///|
fn api_asset(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(api_service_id(value~))
}

///|
fn api_minutes(
  amount~ : Int,
) -> @continuity_forge.TimeSpan raise @continuity_forge.ModelError {
  @continuity_forge.TimeSpan::new(
    amount~,
    unit=@continuity_forge.TimeUnit::Minutes,
  )
}

///|
test "api exposes validated registration and graph operations" {
  let service_id = try! api_service_id(value="checkout")
  let component_id = try! api_component_id(value="postgres")
  let service = try! @continuity_forge.register_service(
    id=service_id,
    name="Checkout",
    owner="commerce",
  )
  let component = try! @continuity_forge.register_component(
    id=component_id,
    name="Postgres",
    technology="database",
  )
  assert_eq(service.name, "Checkout")
  assert_eq(component.technology, "database")
  let service_asset = @continuity_forge.AssetRef::Service(service_id)
  let component_asset = @continuity_forge.AssetRef::Component(component_id)
  let dependency = try! @continuity_forge.define_dependency(
    dependent=service_asset,
    dependency=component_asset,
  )
  let assets = [service_asset, component_asset]
  let _ = try! @continuity_forge.validate_dependencies(assets~, dependencies=[
    dependency,
  ])
  let ordered = try! @continuity_forge.order_dependencies(assets~, dependencies=[
    dependency,
  ])
  match ordered[0] {
    @continuity_forge.AssetRef::Component(_) => ()
    _ => fail("dependency must precede its dependent")
  }
}

///|
test "api exposes impact and recovery planning operations" {
  let api = try! api_asset(value="checkout-api")
  let database = try! api_asset(value="postgres-primary")
  let dependency = try! @continuity_forge.define_dependency(
    dependent=api,
    dependency=database,
  )
  let bia = try! @continuity_forge.assess_business_impact(
    service_id=try! api_service_id(value="checkout"),
    impact_score=85,
    rto=try! api_minutes(amount=30),
    rpo=try! api_minutes(amount=15),
    max_tolerable_downtime=try! api_minutes(amount=120),
  )
  match bia.impact_level {
    @continuity_forge.ImpactLevel::Critical => ()
    _ => fail("high impact score must be critical")
  }
  let impact = try! @continuity_forge.simulate_impact(
    failed_asset=database,
    assets=[api, database],
    dependencies=[dependency],
  )
  assert_eq(impact.affected.length(), 1)
  let item = try! @continuity_forge.RecoveryItem::new(
    asset=database,
    impact_level=@continuity_forge.ImpactLevel::Critical,
    recovery_time=try! api_minutes(amount=20),
    resource="database-team",
  )
  let plan = try! @continuity_forge.plan_recovery(
    items=[item],
    dependencies=[],
    constraints=try! @continuity_forge.RecoveryConstraints::new(
      target_window=try! api_minutes(amount=60),
      available_resources=["database-team"],
    ),
  )
  assert_eq(plan.ordered.length(), 1)
  assert_eq(plan.total_time_minutes, 20)
}

///|
test "api creates validated playbooks and drills" {
  let asset = try! api_asset(value="checkout-api")
  let step = try! @continuity_forge.create_recovery_step(
    id="restore-api",
    asset~,
    owner="platform-team",
    requires_approval=true,
    prerequisites=[],
  )
  let playbook = try! @continuity_forge.create_playbook(
    id="checkout-recovery",
    steps=[step],
  )
  let drill = try! @continuity_forge.create_drill(
    id="checkout-drill",
    playbook~,
  )
  match drill.status {
    @continuity_forge.DrillStatus::Planned => ()
    _ => fail("new drill must be planned")
  }
  try
    @continuity_forge.register_service(
      id=try! api_service_id(value="checkout"),
      name="",
      owner="commerce",
    )
  catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="service.name")
    _ => fail("api must preserve service validation")
  } noraise {
    _ => fail("expected service validation")
  }
  let invalid_id : @continuity_forge.ServiceId = { value: "", }
  try
    @continuity_forge.register_service(
      id=invalid_id,
      name="Checkout",
      owner="commerce",
    )
  catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="service_id")
    _ => fail("wrong error for empty service id")
  } noraise {
    _ => fail("expected service id validation")
  }
}
