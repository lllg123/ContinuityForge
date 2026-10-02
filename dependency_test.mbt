///|
fn service_ref(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(@continuity_forge.ServiceId::new(value~))
}

///|
fn component_ref(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Component(
    @continuity_forge.ComponentId::new(value~),
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
test "dependency order is stable and dependency first" {
  let api = try! service_ref(value="checkout")
  let database = try! component_ref(value="postgres-primary")
  let queue = try! component_ref(value="orders-queue")
  let database_edge = try! @continuity_forge.Dependency::new(
    dependent=api,
    dependency=database,
  )
  let queue_edge = try! @continuity_forge.Dependency::new(
    dependent=api,
    dependency=queue,
  )
  let order = try! @continuity_forge.dependency_order([api, database, queue], [
    database_edge, queue_edge,
  ])
  assert_eq(order.map(asset_key), [
    "component:postgres-primary", "component:orders-queue", "service:checkout",
  ])
}

///|
test "missing assets are rejected" {
  let api = try! service_ref(value="checkout")
  let database = try! component_ref(value="postgres-primary")
  let edge = try! @continuity_forge.Dependency::new(
    dependent=api,
    dependency=database,
  )
  try @continuity_forge.validate_dependency_graph([api], [edge]) catch {
    @continuity_forge.ModelError::MissingAsset(key) =>
      inspect(key, content="component:postgres-primary")
    _ => fail("wrong error for missing asset")
  } noraise {
    _ => fail("expected a missing asset error")
  }
}

///|
test "duplicate assets and edges are rejected" {
  let api = try! service_ref(value="checkout")
  try @continuity_forge.validate_dependency_graph([api, api], []) catch {
    @continuity_forge.ModelError::DuplicateAsset(key) =>
      inspect(key, content="service:checkout")
    _ => fail("wrong error for duplicate asset")
  } noraise {
    _ => fail("expected a duplicate asset error")
  }

  let database = try! component_ref(value="postgres-primary")
  let edge = try! @continuity_forge.Dependency::new(
    dependent=api,
    dependency=database,
  )
  try
    @continuity_forge.validate_dependency_graph([api, database], [edge, edge])
  catch {
    @continuity_forge.ModelError::DuplicateDependency(key) =>
      inspect(key, content="component:postgres-primary -> service:checkout")
    _ => fail("wrong error for duplicate dependency")
  } noraise {
    _ => fail("expected a duplicate dependency error")
  }
}

///|
test "cycles are rejected with a stable cycle member" {
  let api = try! service_ref(value="checkout")
  let database = try! component_ref(value="postgres-primary")
  let to_api = try! @continuity_forge.Dependency::new(
    dependent=api,
    dependency=database,
  )
  let to_database = try! @continuity_forge.Dependency::new(
    dependent=database,
    dependency=api,
  )
  try
    @continuity_forge.validate_dependency_graph([api, database], [
      to_api, to_database,
    ])
  catch {
    @continuity_forge.ModelError::DependencyCycle(key) =>
      inspect(key, content="service:checkout")
    _ => fail("wrong error for dependency cycle")
  } noraise {
    _ => fail("expected a dependency cycle error")
  }
}
