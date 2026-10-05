///|
fn service_asset(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(@continuity_forge.ServiceId::new(value~))
}

///|
fn component_asset(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Component(
    @continuity_forge.ComponentId::new(value~),
  )
}

///|
fn minutes(
  amount~ : Int,
) -> @continuity_forge.TimeSpan raise @continuity_forge.ModelError {
  @continuity_forge.TimeSpan::new(
    amount~,
    unit=@continuity_forge.TimeUnit::Minutes,
  )
}

///|
fn asset_key(asset : @continuity_forge.AssetRef) -> String {
  match asset {
    @continuity_forge.AssetRef::Service(id) => "service:\{id.value}"
    @continuity_forge.AssetRef::Component(id) => "component:\{id.value}"
  }
}

///|
fn main raise {
  let checkout_id = try! @continuity_forge.ServiceId::new(value="checkout-api")
  let database_id = try! @continuity_forge.ComponentId::new(
    value="postgres-primary",
  )
  let checkout = try! service_asset(value="checkout-api")
  let database = try! component_asset(value="postgres-primary")
  let dependency = try! @continuity_forge.define_dependency(
    dependent=checkout,
    dependency=database,
  )

  let _service = try! @continuity_forge.register_service(
    id=checkout_id,
    name="Checkout API",
    owner="Commerce platform",
  )
  let _component = try! @continuity_forge.register_component(
    id=database_id,
    name="Primary Postgres",
    technology="PostgreSQL",
  )
  let assets = [checkout, database]
  try! @continuity_forge.validate_dependencies(assets~, dependencies=[
    dependency,
  ])
  let order = try! @continuity_forge.order_dependencies(assets~, dependencies=[
    dependency,
  ])

  let bia = try! @continuity_forge.assess_business_impact(
    service_id=checkout_id,
    impact_score=85,
    rto=try! minutes(amount=30),
    rpo=try! minutes(amount=15),
    max_tolerable_downtime=try! minutes(amount=120),
  )
  let impact = try! @continuity_forge.simulate_impact(
    failed_asset=database,
    assets~,
    dependencies=[dependency],
  )

  let database_item = try! @continuity_forge.RecoveryItem::new(
    asset=database,
    impact_level=@continuity_forge.ImpactLevel::Critical,
    recovery_time=try! minutes(amount=10),
    resource="database-team",
  )
  let checkout_item = try! @continuity_forge.RecoveryItem::new(
    asset=checkout,
    impact_level=@continuity_forge.ImpactLevel::High,
    recovery_time=try! minutes(amount=20),
    resource="platform-team",
  )
  let recovery = try! @continuity_forge.plan_recovery(
    items=[checkout_item, database_item],
    dependencies=[dependency],
    constraints=try! @continuity_forge.RecoveryConstraints::new(
      target_window=try! minutes(amount=60),
      available_resources=["database-team", "platform-team"],
    ),
  )

  let restore_database = try! @continuity_forge.create_recovery_step(
    id="restore-db",
    asset=database,
    owner="database-team",
    requires_approval=false,
    prerequisites=[],
  )
  let restore_checkout = try! @continuity_forge.create_recovery_step(
    id="restore-api",
    asset=checkout,
    owner="platform-team",
    requires_approval=true,
    prerequisites=["restore-db"],
  )
  let playbook = try! @continuity_forge.create_playbook(
    id="checkout-recovery",
    steps=[restore_database, restore_checkout],
  )
  let drill = try! @continuity_forge.create_drill(
    id="checkout-drill",
    playbook~,
  )
  let drill = drill.start(actor="continuity-operator", timestamp_minutes=540)
  let drill = drill.begin_step(
    step_id="restore-db",
    actor="database-team",
    timestamp_minutes=544,
  )
  let drill = drill.complete_step(
    step_id="restore-db",
    actor="database-team",
    timestamp_minutes=552,
  )
  let drill = drill.begin_step(
    step_id="restore-api",
    actor="platform-team",
    timestamp_minutes=555,
  )
  let drill = drill.approve_step(
    step_id="restore-api",
    actor="resilience-approver",
    timestamp_minutes=557,
  )
  let drill = drill.complete_step(
    step_id="restore-api",
    actor="platform-team",
    timestamp_minutes=568,
  )
  let drill = drill.finish(actor="continuity-operator", timestamp_minutes=570)

  println("ContinuityForge minimal domain example")
  println("dependency order: \{order.map(asset_key).join(", ")}")
  println("BIA score: \{bia.impact_score}/100")
  println("affected assets: \{impact.affected.length()}")
  println(
    "recovery order: \{recovery.ordered.map(item => asset_key(item.asset)).join(", ")}",
  )
  println("recovery window: \{recovery.total_time_minutes} minutes")
  let drill_status = match drill.status {
    @continuity_forge.DrillStatus::Planned => "Planned"
    @continuity_forge.DrillStatus::Running => "Running"
    @continuity_forge.DrillStatus::Completed => "Completed"
  }
  println(
    "drill status: \{drill_status} (\{drill.audit_timeline().length()} events)",
  )
}
