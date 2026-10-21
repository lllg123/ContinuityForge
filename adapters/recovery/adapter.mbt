///|
/// Incident propagation plus a schedule from the generic MoonBit engine.
pub(all) struct RecoveryAnalysis {
  incident : @continuity_forge.IncidentImpact
  problem : @scheduling.SchedulingProblem
  optimization : @scheduling.OptimizationReport
  target_window_minutes : Int
  target_met : Bool
  explanation : Array[String]
}

///|
fn asset_key(asset : @continuity_forge.AssetRef) -> String {
  match asset {
    @continuity_forge.AssetRef::Service(id) => "service:\{id.value}"
    @continuity_forge.AssetRef::Component(id) => "component:\{id.value}"
  }
}

///|
fn recovery_minutes(
  span : @continuity_forge.TimeSpan,
) -> Int raise @continuity_forge.ModelError {
  let factor = match span.unit {
    @continuity_forge.TimeUnit::Minutes => 1
    @continuity_forge.TimeUnit::Hours => 60
    @continuity_forge.TimeUnit::Days => 1440
  }
  if span.amount <= 0 || span.amount > 2147483647 / factor {
    raise @continuity_forge.ModelError::InvalidDuration(
      "recovery duration must fit positive minutes",
    )
  }
  span.amount * factor
}

///|
fn contains_asset(
  assets : Array[@continuity_forge.AssetRef],
  key : String,
) -> Bool {
  for asset in assets {
    if asset_key(asset) == key {
      return true
    }
  }
  false
}

///|
fn impact_priority(level : @continuity_forge.ImpactLevel) -> Int {
  match level {
    @continuity_forge.ImpactLevel::Low => 0
    @continuity_forge.ImpactLevel::Medium => 1
    @continuity_forge.ImpactLevel::High => 2
    @continuity_forge.ImpactLevel::Critical => 3
  }
}

///|
/// Maps recovery assets to generic tasks. Every dependency endpoint must have
/// a recovery item; unrelated assets may remain solely in the impact graph.
pub fn analyze_recovery(
  failed_asset~ : @continuity_forge.AssetRef,
  assets~ : Array[@continuity_forge.AssetRef],
  dependencies~ : Array[@continuity_forge.Dependency],
  items~ : Array[@continuity_forge.RecoveryItem],
  constraints~ : @continuity_forge.RecoveryConstraints,
  search_budget~ : Int,
) -> RecoveryAnalysis raise {
  let incident = @continuity_forge.simulate_incident_impact(
    failed_asset~,
    assets~,
    dependencies~,
  )
  let tasks : Array[@scheduling.Task] = []
  for item in items {
    let id = asset_key(item.asset)
    if !contains_asset(assets, id) {
      raise @continuity_forge.ModelError::MissingAsset(id)
    }
    tasks.push(
      @scheduling.Task::new(
        id~,
        duration=recovery_minutes(item.recovery_time),
        priority=impact_priority(item.impact_level),
        resource_id=item.resource,
      ),
    )
  }
  let generic_dependencies : Array[@scheduling.Dependency] = []
  for edge in dependencies {
    generic_dependencies.push(
      @scheduling.Dependency::new(
        task_id=asset_key(edge.dependent),
        prerequisite_id=asset_key(edge.dependency),
      ),
    )
  }
  let resources : Array[@scheduling.Resource] = []
  for name in constraints.available_resources {
    resources.push(@scheduling.Resource::new(id=name))
  }
  let target_window_minutes = recovery_minutes(constraints.target_window)
  let problem = @scheduling.SchedulingProblem::new(
    tasks~,
    dependencies=generic_dependencies,
    constraints=@scheduling.Constraints::new(resources~, target_makespan=None),
  )
  let optimization = @scheduling.optimize_schedule(problem, search_budget)
  let target_met = optimization.result.makespan <= target_window_minutes
  let explanation = [
    "\{incident.affected.length()} assets affected by \{asset_key(failed_asset)}",
    "scheduled \{optimization.result.makespan}m against target \{target_window_minutes}m",
    "dependency/resource lower bound \{optimization.lower_bound}m",
  ]
  {
    incident,
    problem,
    optimization,
    target_window_minutes,
    target_met,
    explanation,
  }
}
