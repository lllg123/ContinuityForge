///|

///|
fn validate_api_asset(asset : AssetRef) -> Unit raise ModelError {
  match asset {
    Service(id) =>
      if id.value == "" {
        raise ModelError::EmptyField("service_id")
      }
    Component(id) =>
      if id.value == "" {
        raise ModelError::EmptyField("component_id")
      }
  }
}

///|
/// Registers a business service through the validated domain constructor.
pub fn register_service(
  id~ : ServiceId,
  name~ : String,
  owner~ : String,
) -> BusinessService raise ModelError {
  let valid_id = ServiceId::new(value=id.value)
  BusinessService::new(id=valid_id, name~, owner~)
}

///|
/// Registers a technical component through the validated domain constructor.
pub fn register_component(
  id~ : ComponentId,
  name~ : String,
  technology~ : String,
) -> TechnicalComponent raise ModelError {
  let valid_id = ComponentId::new(value=id.value)
  TechnicalComponent::new(id=valid_id, name~, technology~)
}

///|
/// Defines a dependency edge and rejects self-dependencies.
pub fn define_dependency(
  dependent~ : AssetRef,
  dependency~ : AssetRef,
) -> Dependency raise ModelError {
  validate_api_asset(dependent)
  validate_api_asset(dependency)
  Dependency::new(dependent~, dependency~)
}

///|
/// Validates assets and dependencies without mutating the supplied arrays.
pub fn validate_dependencies(
  assets~ : Array[AssetRef],
  dependencies~ : Array[Dependency],
) -> Unit raise ModelError {
  validate_dependency_graph(assets, dependencies)
}

///|
/// Returns a stable dependency-first order after graph validation.
pub fn order_dependencies(
  assets~ : Array[AssetRef],
  dependencies~ : Array[Dependency],
) -> Array[AssetRef] raise ModelError {
  dependency_order(assets, dependencies)
}

///|
/// Creates a business impact assessment with all BIA constraints checked.
pub fn assess_business_impact(
  service_id~ : ServiceId,
  impact_score~ : Int,
  rto~ : TimeSpan,
  rpo~ : TimeSpan,
  max_tolerable_downtime~ : TimeSpan,
) -> BusinessImpactAssessment raise ModelError {
  BusinessImpactAssessment::new(
    service_id~,
    impact_score~,
    rto~,
    rpo~,
    max_tolerable_downtime~,
  )
}

///|
/// Simulates incident propagation after validating the dependency graph.
pub fn simulate_impact(
  failed_asset~ : AssetRef,
  assets~ : Array[AssetRef],
  dependencies~ : Array[Dependency],
) -> IncidentImpact raise ModelError {
  simulate_incident_impact(failed_asset~, assets~, dependencies~)
}

///|
/// Produces a dependency-aware recovery plan under the supplied constraints.
pub fn plan_recovery(
  items~ : Array[RecoveryItem],
  dependencies~ : Array[Dependency],
  constraints~ : RecoveryConstraints,
) -> RecoveryPlan raise ModelError {
  prioritize_recovery(items~, dependencies~, constraints~)
}

///|
/// Creates one validated recovery step for a playbook.
pub fn create_recovery_step(
  id~ : String,
  asset~ : AssetRef,
  owner~ : String,
  requires_approval~ : Bool,
  prerequisites~ : Array[String],
) -> RecoveryStep raise ModelError {
  validate_api_asset(asset)
  RecoveryStep::new(id~, asset~, owner~, requires_approval~, prerequisites~)
}

///|
/// Creates a validated recovery playbook.
pub fn create_playbook(
  id~ : String,
  steps~ : Array[RecoveryStep],
) -> RecoveryPlaybook raise ModelError {
  RecoveryPlaybook::new(id~, steps~)
}

///|
/// Creates a planned drill for a validated recovery playbook.
pub fn create_drill(
  id~ : String,
  playbook~ : RecoveryPlaybook,
) -> RecoveryDrill raise ModelError {
  RecoveryDrill::new(id~, playbook~)
}
