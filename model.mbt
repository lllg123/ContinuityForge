///|
/// Errors raised while constructing the continuity domain model.
pub(all) suberror ModelError {
  EmptyField(String)
  SelfDependency(String)
  DuplicateAsset(String)
  MissingAsset(String)
  DuplicateDependency(String)
  DependencyCycle(String)
  InvalidImpactScore(String)
  InvalidDuration(String)
  InvalidBia(String)
  RecoveryResourceConflict(String)
  RecoveryTargetUnmet(String)
  PlaybookValidation(String)
  StepNotFound(String)
  StepBlocked(String)
  InvalidStepTransition(String)
  DrillValidation(String)
  InvalidDrillTransition(String)
  StorageValidation(String)
  ProjectNotFound(String)
  DuplicateAuditRecord(String)
}

///|
/// Stable identifier for a business service.
pub(all) struct ServiceId {
  value : String
}

///|
/// Creates a service identifier after checking that it is present.
pub fn ServiceId::new(value~ : String) -> ServiceId raise ModelError {
  if value == "" {
    raise ModelError::EmptyField("service_id")
  }
  { value, }
}

///|
/// Stable identifier for a technical component.
pub(all) struct ComponentId {
  value : String
}

///|
/// Creates a component identifier after checking that it is present.
pub fn ComponentId::new(value~ : String) -> ComponentId raise ModelError {
  if value == "" {
    raise ModelError::EmptyField("component_id")
  }
  { value, }
}

///|
/// A business capability or service tracked by the continuity platform.
pub(all) struct BusinessService {
  id : ServiceId
  name : String
  owner : String
}

///|
/// Creates a business service with the fields required for ownership and reporting.
pub fn BusinessService::new(
  id~ : ServiceId,
  name~ : String,
  owner~ : String,
) -> BusinessService raise ModelError {
  if name == "" {
    raise ModelError::EmptyField("service.name")
  }
  if owner == "" {
    raise ModelError::EmptyField("service.owner")
  }
  { id, name, owner, }
}

///|
/// A technical component that supports one or more business services.
pub(all) struct TechnicalComponent {
  id : ComponentId
  name : String
  technology : String
}

///|
/// Creates a technical component with a descriptive technology field.
pub fn TechnicalComponent::new(
  id~ : ComponentId,
  name~ : String,
  technology~ : String,
) -> TechnicalComponent raise ModelError {
  if name == "" {
    raise ModelError::EmptyField("component.name")
  }
  if technology == "" {
    raise ModelError::EmptyField("component.technology")
  }
  { id, name, technology, }
}

///|
/// A dependency endpoint. The dependency graph is validated in a later stage.
pub(all) enum AssetRef {
  Service(ServiceId)
  Component(ComponentId)
}

///|
fn asset_ref_key(asset : AssetRef) -> String {
  match asset {
    Service(id) => "service:\{id.value}"
    Component(id) => "component:\{id.value}"
  }
}

///|
/// A directed dependency where `dependent` requires `dependency` first.
pub(all) struct Dependency {
  dependent : AssetRef
  dependency : AssetRef
}

///|
/// Creates a dependency edge and rejects an endpoint depending on itself.
pub fn Dependency::new(
  dependent~ : AssetRef,
  dependency~ : AssetRef,
) -> Dependency raise ModelError {
  if asset_ref_key(dependent) == asset_ref_key(dependency) {
    raise ModelError::SelfDependency(asset_ref_key(dependent))
  }
  { dependent, dependency, }
}
