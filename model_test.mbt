///|
fn service_id(
  value~ : String,
) -> @continuity_forge.ServiceId raise @continuity_forge.ModelError {
  @continuity_forge.ServiceId::new(value~)
}

///|
fn component_id(
  value~ : String,
) -> @continuity_forge.ComponentId raise @continuity_forge.ModelError {
  @continuity_forge.ComponentId::new(value~)
}

///|
test "services and components preserve stable identifiers" {
  let service = try! @continuity_forge.BusinessService::new(
    id=try! service_id(value="checkout"),
    name="Checkout",
    owner="payments",
  )
  let component = try! @continuity_forge.TechnicalComponent::new(
    id=try! component_id(value="postgres-primary"),
    name="Primary database",
    technology="PostgreSQL",
  )
  assert_eq(service.id.value, "checkout")
  assert_eq(service.owner, "payments")
  assert_eq(component.id.value, "postgres-primary")
  assert_eq(component.technology, "PostgreSQL")
}

///|
test "empty identifiers report the related field" {
  try @continuity_forge.ServiceId::new(value="") catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="service_id")
    _ => fail("wrong error for empty service id")
  } noraise {
    _ => fail("expected an empty service id error")
  }
  try @continuity_forge.ComponentId::new(value="") catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="component_id")
    _ => fail("wrong error for empty component id")
  } noraise {
    _ => fail("expected an empty component id error")
  }
}

///|
test "service and component metadata is validated" {
  let service_id = try! service_id(value="orders")
  try
    @continuity_forge.BusinessService::new(
      id=service_id,
      name="",
      owner="commerce",
    )
  catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="service.name")
    _ => fail("wrong error for empty service name")
  } noraise {
    _ => fail("expected an empty service name error")
  }
  try
    @continuity_forge.BusinessService::new(
      id=service_id,
      name="Orders",
      owner="",
    )
  catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="service.owner")
    _ => fail("wrong error for empty service owner")
  } noraise {
    _ => fail("expected an empty service owner error")
  }

  let component_id = try! component_id(value="queue")
  try
    @continuity_forge.TechnicalComponent::new(
      id=component_id,
      name="Queue",
      technology="",
    )
  catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="component.technology")
    _ => fail("wrong error for empty technology")
  } noraise {
    _ => fail("expected an empty technology error")
  }
}

///|
test "dependency edges connect services and components" {
  let service = @continuity_forge.AssetRef::Service(
    try! service_id(value="checkout"),
  )
  let database = @continuity_forge.AssetRef::Component(
    try! component_id(value="postgres-primary"),
  )
  let edge = try! @continuity_forge.Dependency::new(
    dependent=service,
    dependency=database,
  )
  match edge.dependent {
    @continuity_forge.AssetRef::Service(id) => assert_eq(id.value, "checkout")
    _ => fail("wrong dependent endpoint")
  }
  match edge.dependency {
    @continuity_forge.AssetRef::Component(id) =>
      assert_eq(id.value, "postgres-primary")
    _ => fail("wrong dependency endpoint")
  }
}

///|
test "self dependencies are rejected with a stable endpoint key" {
  let service = @continuity_forge.AssetRef::Service(
    try! service_id(value="checkout"),
  )
  try
    @continuity_forge.Dependency::new(dependent=service, dependency=service)
  catch {
    @continuity_forge.ModelError::SelfDependency(key) =>
      inspect(key, content="service:checkout")
    _ => fail("wrong error for self dependency")
  } noraise {
    _ => fail("expected a self dependency error")
  }
}
