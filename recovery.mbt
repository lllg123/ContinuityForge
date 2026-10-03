///|
/// A recoverable asset with its BIA-derived priority and resource requirement.
pub(all) struct RecoveryItem {
  asset : AssetRef
  impact_level : ImpactLevel
  recovery_time : TimeSpan
  resource : String
}

///|
/// Creates a recovery item with a positive estimated recovery duration.
pub fn RecoveryItem::new(
  asset~ : AssetRef,
  impact_level~ : ImpactLevel,
  recovery_time~ : TimeSpan,
  resource~ : String,
) -> RecoveryItem raise ModelError {
  if recovery_time.amount < 0 {
    raise ModelError::InvalidDuration(
      "recovery_time.amount must be non-negative",
    )
  }
  if recovery_time.amount == 0 {
    raise ModelError::InvalidDuration("recovery_time must be positive")
  }
  if resource == "" {
    raise ModelError::EmptyField("recovery.resource")
  }
  { asset, impact_level, recovery_time, resource, }
}

///|
/// Resource and total-window limits for a recovery plan.
pub(all) struct RecoveryConstraints {
  target_window : TimeSpan
  available_resources : Array[String]
}

///|
/// Creates recovery constraints and rejects duplicate or empty resources.
pub fn RecoveryConstraints::new(
  target_window~ : TimeSpan,
  available_resources~ : Array[String],
) -> RecoveryConstraints raise ModelError {
  if target_window.amount < 0 {
    raise ModelError::InvalidDuration(
      "recovery.target_window.amount must be non-negative",
    )
  }
  if target_window.amount == 0 {
    raise ModelError::InvalidDuration("recovery.target_window must be positive")
  }
  for i in 0..<available_resources.length() {
    if available_resources[i] == "" {
      raise ModelError::RecoveryResourceConflict(
        "available resource cannot be empty",
      )
    }
    for j in 0..<i {
      if available_resources[i] == available_resources[j] {
        raise ModelError::RecoveryResourceConflict(
          "duplicate available resource: \{available_resources[i]}",
        )
      }
    }
  }
  { target_window, available_resources, }
}

///|
/// The dependency-respecting recovery order and its total estimated duration.
pub(all) struct RecoveryPlan {
  ordered : Array[RecoveryItem]
  total_time_minutes : Int
  target_window_minutes : Int
}

///|
fn impact_rank(level : ImpactLevel) -> Int {
  match level {
    Low => 0
    Medium => 1
    High => 2
    Critical => 3
  }
}

///|
fn has_resource(resources : Array[String], resource : String) -> Bool {
  let mut found = false
  for available in resources {
    if available == resource {
      found = true
    }
  }
  found
}

///|
fn validate_recovery_constraints(
  items : Array[RecoveryItem],
  constraints : RecoveryConstraints,
) -> Unit raise ModelError {
  if constraints.target_window.amount <= 0 {
    raise ModelError::InvalidDuration("recovery.target_window must be positive")
  }
  for item in items {
    if item.recovery_time.amount <= 0 {
      raise ModelError::InvalidDuration("recovery_time must be positive")
    }
    if item.resource == "" {
      raise ModelError::EmptyField("recovery.resource")
    }
    if !has_resource(constraints.available_resources, item.resource) {
      raise ModelError::RecoveryResourceConflict(
        "resource unavailable for \{asset_ref_key(item.asset)}: \{item.resource}",
      )
    }
  }
}

///|
fn prerequisites_ready(
  candidate : AssetRef,
  assets : Array[AssetRef],
  dependencies : Array[Dependency],
  selected : Array[Bool],
) -> Bool {
  let mut ready = true
  for dependency in dependencies {
    if asset_ref_key(dependency.dependent) == asset_ref_key(candidate) {
      let dependency_index = match
        asset_index(assets, asset_ref_key(dependency.dependency)) {
        Some(index) => index
        None => {
          ready = false
          -1
        }
      }
      if dependency_index >= 0 && !selected[dependency_index] {
        ready = false
      }
    }
  }
  ready
}

///|
fn is_better_candidate(
  candidate : RecoveryItem,
  current : RecoveryItem,
) -> Bool {
  let candidate_rank = impact_rank(candidate.impact_level)
  let current_rank = impact_rank(current.impact_level)
  if candidate_rank != current_rank {
    candidate_rank > current_rank
  } else {
    candidate.recovery_time.as_minutes() < current.recovery_time.as_minutes()
  }
}

///|
/// Prioritizes recovery while honoring dependencies, resources and a time window.
pub fn prioritize_recovery(
  items~ : Array[RecoveryItem],
  dependencies~ : Array[Dependency],
  constraints~ : RecoveryConstraints,
) -> RecoveryPlan raise ModelError {
  validate_recovery_constraints(items, constraints)
  let assets : Array[AssetRef] = []
  for item in items {
    assets.push(item.asset)
  }
  let (adjacency, _) = build_adjacency(assets, dependencies)
  ensure_acyclic(assets, adjacency)
  let selected : Array[Bool] = []
  for _ in 0..<items.length() {
    selected.push(false)
  }
  let ordered : Array[RecoveryItem] = []
  let mut total_time_minutes = 0
  for _ in 0..<items.length() {
    let mut chosen : Int? = None
    for i, item in items {
      if !selected[i] &&
        prerequisites_ready(item.asset, assets, dependencies, selected) {
        match chosen {
          None => chosen = Some(i)
          Some(current) =>
            if is_better_candidate(item, items[current]) {
              chosen = Some(i)
            }
        }
      }
    }
    let index = match chosen {
      Some(index) => index
      None =>
        raise ModelError::DependencyCycle(
          "recovery prerequisites cannot be satisfied",
        )
    }
    let item = items[index]
    let next_total = total_time_minutes + item.recovery_time.as_minutes()
    if next_total > constraints.target_window.as_minutes() {
      raise ModelError::RecoveryTargetUnmet(
        "recovery window exceeded at \{asset_ref_key(item.asset)}",
      )
    }
    selected[index] = true
    ordered.push(item)
    total_time_minutes = next_total
  }
  {
    ordered,
    total_time_minutes,
    target_window_minutes: constraints.target_window.as_minutes(),
  }
}
