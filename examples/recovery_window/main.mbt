///|
fn asset_key(asset : @continuity_forge.AssetRef) -> String {
  match asset {
    @continuity_forge.AssetRef::Service(id) => "service:\{id.value}"
    @continuity_forge.AssetRef::Component(id) => "component:\{id.value}"
  }
}

///|
fn minutes(amount : Int) -> @continuity_forge.TimeSpan raise {
  @continuity_forge.TimeSpan::new(
    amount~,
    unit=@continuity_forge.TimeUnit::Minutes,
  )
}

///|
fn item(
  asset : @continuity_forge.AssetRef,
  level : @continuity_forge.ImpactLevel,
  duration : Int,
  resource : String,
) -> @continuity_forge.RecoveryItem raise {
  @continuity_forge.RecoveryItem::new(
    asset~,
    impact_level=level,
    recovery_time=minutes(duration),
    resource~,
  )
}

///|
fn main raise {
  let database = @continuity_forge.AssetRef::Component(
    @continuity_forge.ComponentId::new(value="postgres-primary"),
  )
  let api = @continuity_forge.AssetRef::Service(
    @continuity_forge.ServiceId::new(value="checkout-api"),
  )
  let worker = @continuity_forge.AssetRef::Service(
    @continuity_forge.ServiceId::new(value="checkout-worker"),
  )
  let router = @continuity_forge.AssetRef::Component(
    @continuity_forge.ComponentId::new(value="edge-router"),
  )
  let plan = @continuity_forge.plan_recovery(
    items=[
      item(worker, @continuity_forge.ImpactLevel::Medium, 15, "compute"),
      item(router, @continuity_forge.ImpactLevel::Low, 25, "network"),
      item(api, @continuity_forge.ImpactLevel::High, 20, "compute"),
      item(database, @continuity_forge.ImpactLevel::Critical, 10, "database"),
    ],
    dependencies=[
      @continuity_forge.define_dependency(dependent=api, dependency=database),
    ],
    constraints=@continuity_forge.RecoveryConstraints::new(
      target_window=minutes(45),
      available_resources=["database", "compute", "network"],
    ),
  )
  println("asset | resource | start | finish")
  for entry in plan.schedule {
    println(
      "\{asset_key(entry.item.asset)} | \{entry.item.resource} | \{entry.start_minutes} | \{entry.end_minutes}",
    )
  }
  println("dependency lower bound: \{plan.dependency_lower_bound_minutes}m")
  println("resource lower bound: \{plan.resource_lower_bound_minutes}m")
  println(
    "elapsed recovery window: \{plan.total_time_minutes}m / \{plan.target_window_minutes}m (slack \{plan.slack_minutes}m)",
  )
}
