///|
fn impact_service(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(@continuity_forge.ServiceId::new(value~))
}

///|
fn impact_component(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Component(
    @continuity_forge.ComponentId::new(value~),
  )
}

///|
fn impact_key(asset : @continuity_forge.AssetRef) -> String {
  match asset {
    @continuity_forge.AssetRef::Service(id) => "service:\{id.value}"
    @continuity_forge.AssetRef::Component(id) => "component:\{id.value}"
  }
}

///|
fn impact_edge(
  dependent~ : @continuity_forge.AssetRef,
  dependency~ : @continuity_forge.AssetRef,
) -> @continuity_forge.Dependency raise @continuity_forge.ModelError {
  @continuity_forge.Dependency::new(dependent~, dependency~)
}

///|
test "incident impact follows a dependency chain" {
  let database = try! impact_component(value="postgres-primary")
  let api = try! impact_service(value="checkout-api")
  let checkout = try! impact_service(value="checkout")
  let report = try! @continuity_forge.simulate_incident_impact(
    failed_asset=database,
    assets=[checkout, database, api],
    dependencies=[
      try! impact_edge(dependent=api, dependency=database),
      try! impact_edge(dependent=checkout, dependency=api),
    ],
  )
  assert_eq(report.affected.map(impact_key), [
    "service:checkout-api", "service:checkout",
  ])
  assert_eq(report.paths.length(), 2)
  assert_eq(report.paths[0].path.map(impact_key), [
    "component:postgres-primary", "service:checkout-api",
  ])
  assert_eq(report.paths[1].path.map(impact_key), [
    "component:postgres-primary", "service:checkout-api", "service:checkout",
  ])
}

///|
test "diamond propagation deduplicates the converging asset" {
  let database = try! impact_component(value="postgres-primary")
  let api = try! impact_service(value="checkout-api")
  let worker = try! impact_service(value="checkout-worker")
  let checkout = try! impact_service(value="checkout")
  let report = try! @continuity_forge.simulate_incident_impact(
    failed_asset=database,
    assets=[checkout, database, api, worker],
    dependencies=[
      try! impact_edge(dependent=api, dependency=database),
      try! impact_edge(dependent=worker, dependency=database),
      try! impact_edge(dependent=checkout, dependency=api),
      try! impact_edge(dependent=checkout, dependency=worker),
    ],
  )
  assert_eq(report.affected.map(impact_key), [
    "service:checkout-api", "service:checkout-worker", "service:checkout",
  ])
  assert_eq(report.paths.length(), 3)
  assert_eq(report.paths[2].path.map(impact_key), [
    "component:postgres-primary", "service:checkout-api", "service:checkout",
  ])
}

///|
test "assets without dependents produce an empty impact set" {
  let database = try! impact_component(value="postgres-primary")
  let report = try! @continuity_forge.simulate_incident_impact(
    failed_asset=database,
    assets=[database],
    dependencies=[],
  )
  assert_eq(report.affected.length(), 0)
  assert_eq(report.paths.length(), 0)
}

///|
test "missing failed assets are rejected" {
  let database = try! impact_component(value="postgres-primary")
  let missing = try! impact_component(value="replica")
  try
    @continuity_forge.simulate_incident_impact(
      failed_asset=missing,
      assets=[database],
      dependencies=[],
    )
  catch {
    @continuity_forge.ModelError::MissingAsset(key) =>
      inspect(key, content="component:replica")
    _ => fail("wrong error for missing failed asset")
  } noraise {
    _ => fail("expected a missing failed asset error")
  }
}
