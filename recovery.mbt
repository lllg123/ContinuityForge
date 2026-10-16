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
/// A scheduled, non-preemptive recovery task on one exclusive resource.
pub(all) struct RecoveryScheduleEntry {
  item : RecoveryItem
  start_minutes : Int
  end_minutes : Int
}

///|
/// A dependency-aware resource schedule and its elapsed recovery window.
pub(all) struct RecoveryPlan {
  ordered : Array[RecoveryItem]
  schedule : Array[RecoveryScheduleEntry]
  total_time_minutes : Int
  target_window_minutes : Int
  dependency_lower_bound_minutes : Int
  resource_lower_bound_minutes : Int
  slack_minutes : Int
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
fn checked_recovery_minutes(span : TimeSpan) -> Int raise ModelError {
  let factor = match span.unit {
    Minutes => 1
    Hours => 60
    Days => 1440
  }
  if span.amount <= 0 || span.amount > 2147483647 / factor {
    raise ModelError::InvalidDuration(
      "recovery duration must fit positive minutes",
    )
  }
  span.amount * factor
}

///|
fn checked_recovery_sum(left : Int, right : Int) -> Int raise ModelError {
  if right > 2147483647 - left {
    raise ModelError::InvalidDuration("recovery schedule exceeds minute range")
  }
  left + right
}

///|
fn better_recovery_candidate(
  candidate : Int,
  current : Int,
  items : Array[RecoveryItem],
  downstream_rank : Array[Int],
  remaining_path : Array[Int],
  durations : Array[Int],
) -> Bool {
  if downstream_rank[candidate] != downstream_rank[current] {
    downstream_rank[candidate] > downstream_rank[current]
  } else if remaining_path[candidate] - durations[candidate] !=
    remaining_path[current] - durations[current] {
    remaining_path[candidate] - durations[candidate] >
    remaining_path[current] - durations[current]
  } else if impact_rank(items[candidate].impact_level) !=
    impact_rank(items[current].impact_level) {
    impact_rank(items[candidate].impact_level) >
    impact_rank(items[current].impact_level)
  } else if durations[candidate] != durations[current] {
    durations[candidate] < durations[current]
  } else {
    asset_ref_key(items[candidate].asset) < asset_ref_key(items[current].asset)
  }
}

///|
/// Builds a deterministic earliest-slot list schedule. Each resource has one
/// non-preemptive slot; distinct resources can work in parallel. The ordering
/// heuristic is not an optimality proof for the resulting makespan.
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
  let durations : Array[Int] = []
  for item in items {
    durations.push(checked_recovery_minutes(item.recovery_time))
  }
  let target_window_minutes = checked_recovery_minutes(
    constraints.target_window,
  )
  let topological = dependency_order(assets, dependencies)
  let downstream_rank : Array[Int] = []
  let remaining_path : Array[Int] = []
  for i in 0..<items.length() {
    downstream_rank.push(impact_rank(items[i].impact_level))
    remaining_path.push(durations[i])
  }
  for position in 0..<topological.length() {
    let index = match
      asset_index(
        assets,
        asset_ref_key(topological[topological.length() - 1 - position]),
      ) {
      Some(value) => value
      None => abort("validated recovery asset disappeared")
    }
    for dependent in adjacency[index] {
      if downstream_rank[dependent] > downstream_rank[index] {
        downstream_rank[index] = downstream_rank[dependent]
      }
      let path = checked_recovery_sum(
        durations[index],
        remaining_path[dependent],
      )
      if path > remaining_path[index] {
        remaining_path[index] = path
      }
    }
  }
  let mut dependency_lower_bound_minutes = 0
  for path in remaining_path {
    if path > dependency_lower_bound_minutes {
      dependency_lower_bound_minutes = path
    }
  }
  let mut resource_lower_bound_minutes = 0
  for resource in constraints.available_resources {
    let mut load = 0
    for i, item in items {
      if item.resource == resource {
        load = checked_recovery_sum(load, durations[i])
      }
    }
    if load > resource_lower_bound_minutes {
      resource_lower_bound_minutes = load
    }
  }
  let lower_bound = if dependency_lower_bound_minutes >
    resource_lower_bound_minutes {
    dependency_lower_bound_minutes
  } else {
    resource_lower_bound_minutes
  }
  if lower_bound > target_window_minutes {
    raise ModelError::RecoveryTargetUnmet(
      "target \{target_window_minutes}m is below unavoidable lower bound \{lower_bound}m (dependency \{dependency_lower_bound_minutes}m, resource \{resource_lower_bound_minutes}m)",
    )
  }
  let selected : Array[Bool] = []
  let completion : Array[Int] = []
  for _ in 0..<items.length() {
    selected.push(false)
    completion.push(0)
  }
  let ordered : Array[RecoveryItem] = []
  let schedule : Array[RecoveryScheduleEntry] = []
  let mut total_time_minutes = 0
  for _ in 0..<items.length() {
    let mut chosen : Int? = None
    for i, item in items {
      if !selected[i] &&
        prerequisites_ready(item.asset, assets, dependencies, selected) {
        match chosen {
          None => chosen = Some(i)
          Some(current) =>
            if better_recovery_candidate(
                i, current, items, downstream_rank, remaining_path, durations,
              ) {
              chosen = Some(i)
            }
        }
      }
    }
    let index = match chosen {
      Some(value) => value
      None =>
        raise ModelError::DependencyCycle(
          "recovery prerequisites cannot be satisfied",
        )
    }
    let item = items[index]
    let mut start_minutes = 0
    for dependency in dependencies {
      if asset_ref_key(dependency.dependent) == asset_ref_key(item.asset) {
        let predecessor = match
          asset_index(assets, asset_ref_key(dependency.dependency)) {
          Some(value) => value
          None => abort("validated recovery dependency disappeared")
        }
        if completion[predecessor] > start_minutes {
          start_minutes = completion[predecessor]
        }
      }
    }
    let mut searching = true
    while searching {
      searching = false
      let candidate_end = checked_recovery_sum(start_minutes, durations[index])
      for booked in schedule {
        if booked.item.resource == item.resource &&
          start_minutes < booked.end_minutes &&
          booked.start_minutes < candidate_end {
          start_minutes = booked.end_minutes
          searching = true
          break
        }
      }
    }
    let end_minutes = checked_recovery_sum(start_minutes, durations[index])
    selected[index] = true
    completion[index] = end_minutes
    ordered.push(item)
    schedule.push({ item, start_minutes, end_minutes, })
    if end_minutes > total_time_minutes {
      total_time_minutes = end_minutes
    }
  }
  if total_time_minutes > target_window_minutes {
    raise ModelError::RecoveryTargetUnmet(
      "scheduled \{total_time_minutes}m exceeds target \{target_window_minutes}m; unavoidable lower bound \{lower_bound}m (dependency \{dependency_lower_bound_minutes}m, resource \{resource_lower_bound_minutes}m)",
    )
  }
  {
    ordered,
    schedule,
    total_time_minutes,
    target_window_minutes,
    dependency_lower_bound_minutes,
    resource_lower_bound_minutes,
    slack_minutes: target_window_minutes - total_time_minutes,
  }
}
