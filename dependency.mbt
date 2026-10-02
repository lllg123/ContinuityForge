///|
fn asset_index(assets : Array[AssetRef], key : String) -> Int? {
  let mut result : Int? = None
  for i, asset in assets {
    if result is None && asset_ref_key(asset) == key {
      result = Some(i)
    }
  }
  result
}

///|
fn validate_assets(assets : Array[AssetRef]) -> Unit raise ModelError {
  for i in 0..<assets.length() {
    let key = asset_ref_key(assets[i])
    let value = match assets[i] {
      Service(id) => id.value
      Component(id) => id.value
    }
    if value == "" {
      let field = match assets[i] {
        Service(_) => "service_id"
        Component(_) => "component_id"
      }
      raise ModelError::EmptyField(field)
    }
    for j in 0..<i {
      if asset_ref_key(assets[j]) == key {
        raise ModelError::DuplicateAsset(key)
      }
    }
  }
}

///|
fn build_adjacency(
  assets : Array[AssetRef],
  dependencies : Array[Dependency],
) -> (Array[Array[Int]], Array[Int]) raise ModelError {
  validate_assets(assets)
  let adjacency : Array[Array[Int]] = []
  let indegree : Array[Int] = []
  for _ in 0..<assets.length() {
    adjacency.push([])
    indegree.push(0)
  }
  for dependency in dependencies {
    let dependency_key = asset_ref_key(dependency.dependency)
    let dependent_key = asset_ref_key(dependency.dependent)
    if dependency_key == dependent_key {
      raise ModelError::SelfDependency(dependency_key)
    }
    let dependency_index = match asset_index(assets, dependency_key) {
      Some(index) => index
      None => raise ModelError::MissingAsset(dependency_key)
    }
    let dependent_index = match asset_index(assets, dependent_key) {
      Some(index) => index
      None => raise ModelError::MissingAsset(dependent_key)
    }
    for existing in adjacency[dependency_index] {
      if existing == dependent_index {
        raise ModelError::DuplicateDependency(
          "\{dependency_key} -> \{dependent_key}",
        )
      }
    }
    adjacency[dependency_index].push(dependent_index)
    indegree[dependent_index] = indegree[dependent_index] + 1
  }
  (adjacency, indegree)
}

///|
fn detect_cycle(
  node : Int,
  assets : Array[AssetRef],
  adjacency : Array[Array[Int]],
  state : Array[Int],
) -> Unit raise ModelError {
  if state[node] == 1 {
    raise ModelError::DependencyCycle(asset_ref_key(assets[node]))
  }
  if state[node] == 2 {
    ()
  } else {
    state[node] = 1
    for dependent in adjacency[node] {
      detect_cycle(dependent, assets, adjacency, state)
    }
    state[node] = 2
  }
}

///|
fn ensure_acyclic(
  assets : Array[AssetRef],
  adjacency : Array[Array[Int]],
) -> Unit raise ModelError {
  let state : Array[Int] = []
  for _ in 0..<assets.length() {
    state.push(0)
  }
  for i in 0..<assets.length() {
    if state[i] == 0 {
      detect_cycle(i, assets, adjacency, state)
    }
  }
}

///|
/// Returns assets in a stable dependency-first topological order.
pub fn dependency_order(
  assets : Array[AssetRef],
  dependencies : Array[Dependency],
) -> Array[AssetRef] raise ModelError {
  let (adjacency, indegree) = build_adjacency(assets, dependencies)
  ensure_acyclic(assets, adjacency)
  let ready : Array[Int] = []
  for i in 0..<assets.length() {
    if indegree[i] == 0 {
      ready.push(i)
    }
  }
  let order : Array[AssetRef] = []
  let mut cursor = 0
  while cursor < ready.length() {
    let node = ready[cursor]
    cursor = cursor + 1
    order.push(assets[node])
    for dependent in adjacency[node] {
      indegree[dependent] = indegree[dependent] - 1
      if indegree[dependent] == 0 {
        ready.push(dependent)
      }
    }
  }
  order
}

///|
/// Validates all assets and dependency edges without returning an order.
pub fn validate_dependency_graph(
  assets : Array[AssetRef],
  dependencies : Array[Dependency],
) -> Unit raise ModelError {
  let _ = dependency_order(assets, dependencies)
}
