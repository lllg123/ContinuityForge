///|
/// One stable propagation path from the failed asset to an affected asset.
pub(all) struct ImpactPath {
  affected_asset : AssetRef
  path : Array[AssetRef]
}

///|
/// Deduplicated impact propagation results for one simulated incident.
pub(all) struct IncidentImpact {
  failed_asset : AssetRef
  affected : Array[AssetRef]
  paths : Array[ImpactPath]
}

///|
fn extend_path(path : Array[AssetRef], asset : AssetRef) -> Array[AssetRef] {
  let result : Array[AssetRef] = []
  for item in path {
    result.push(item)
  }
  result.push(asset)
  result
}

///|
/// Simulates failure propagation along dependency edges.
///
/// Each affected asset is returned once. Paths use breadth-first traversal and
/// preserve the dependency input order, making the result deterministic.
pub fn simulate_incident_impact(
  failed_asset~ : AssetRef,
  assets~ : Array[AssetRef],
  dependencies~ : Array[Dependency],
) -> IncidentImpact raise ModelError {
  let (adjacency, _) = build_adjacency(assets, dependencies)
  ensure_acyclic(assets, adjacency)
  let failed_key = asset_ref_key(failed_asset)
  let failed_index = match asset_index(assets, failed_key) {
    Some(index) => index
    None => raise ModelError::MissingAsset(failed_key)
  }
  let visited : Array[Bool] = []
  for _ in 0..<assets.length() {
    visited.push(false)
  }
  visited[failed_index] = true
  let queue_nodes : Array[Int] = [failed_index]
  let root_path : Array[AssetRef] = [failed_asset]
  let queue_paths : Array[Array[AssetRef]] = [root_path]
  let affected : Array[AssetRef] = []
  let paths : Array[ImpactPath] = []
  let mut cursor = 0
  while cursor < queue_nodes.length() {
    let node = queue_nodes[cursor]
    let current_path = queue_paths[cursor]
    cursor = cursor + 1
    for dependent in adjacency[node] {
      if !visited[dependent] {
        visited[dependent] = true
        let next_path = extend_path(current_path, assets[dependent])
        queue_nodes.push(dependent)
        queue_paths.push(next_path)
        let affected_asset = assets[dependent]
        affected.push(affected_asset)
        paths.push({ affected_asset, path: next_path, })
      }
    }
  }
  { failed_asset, affected, paths, }
}
