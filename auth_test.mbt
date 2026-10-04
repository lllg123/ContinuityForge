///|
fn auth_user(
  id~ : String,
  username~ : String,
  role~ : @continuity_forge.Role,
) -> @continuity_forge.LocalUser raise @continuity_forge.ModelError {
  @continuity_forge.LocalUser::new(id~, username~, role~)
}

///|
test "roles grant only their domain permissions" {
  let store = @continuity_forge.LocalAuthStore::new()
  let viewer = try! auth_user(
    id="user-viewer",
    username="viewer",
    role=@continuity_forge.Role::Viewer,
  )
  let operator = try! auth_user(
    id="user-operator",
    username="operator",
    role=@continuity_forge.Role::Operator,
  )
  let approver = try! auth_user(
    id="user-approver",
    username="approver",
    role=@continuity_forge.Role::Approver,
  )
  let administrator = try! auth_user(
    id="user-admin",
    username="administrator",
    role=@continuity_forge.Role::Administrator,
  )
  let registered = try! store.register_user(user=viewer)
  let registered = try! registered.register_user(user=operator)
  let registered = try! registered.register_user(user=approver)
  let registered = try! registered.register_user(user=administrator)
  assert_true(
    registered.can(
      user_id="user-viewer",
      permission=@continuity_forge.Permission::ReadProjects,
    ),
  )
  assert_false(
    registered.can(
      user_id="user-viewer",
      permission=@continuity_forge.Permission::RunDrills,
    ),
  )
  try! registered.authorize(
    user_id="user-operator",
    permission=@continuity_forge.Permission::RunDrills,
  )
  try
    registered.authorize(
      user_id="user-operator",
      permission=@continuity_forge.Permission::ApproveRecovery,
    )
  catch {
    @continuity_forge.ModelError::AccessDenied(message) =>
      inspect(message, content="user operator lacks approve_recovery")
    _ => fail("wrong error for insufficient role")
  } noraise {
    _ => fail("expected operator approval denial")
  }
  try! registered.authorize(
    user_id="user-approver",
    permission=@continuity_forge.Permission::ApproveRecovery,
  )
  try! registered.authorize(
    user_id="user-admin",
    permission=@continuity_forge.Permission::ManageUsers,
  )
}

///|
test "local users can be suspended and reactivated" {
  let user = try! auth_user(
    id="user-operator",
    username="operator",
    role=@continuity_forge.Role::Operator,
  )
  let store = try! @continuity_forge.LocalAuthStore::new().register_user(user~)
  let suspended = try! store.deactivate_user(user_id="user-operator")
  assert_false(
    suspended.can(
      user_id="user-operator",
      permission=@continuity_forge.Permission::ReadAudit,
    ),
  )
  try
    suspended.authorize(
      user_id="user-operator",
      permission=@continuity_forge.Permission::ReadAudit,
    )
  catch {
    @continuity_forge.ModelError::AccessDenied(message) =>
      inspect(message, content="user operator is inactive")
    _ => fail("wrong error for inactive user")
  } noraise {
    _ => fail("expected inactive user denial")
  }
  let active = try! suspended.activate_user(user_id="user-operator")
  try! active.authorize(
    user_id="user-operator",
    permission=@continuity_forge.Permission::ReadAudit,
  )
  match active.get_user(user_id="user-operator") {
    Some(value) => assert_true(value.active)
    None => fail("reactivated user must be readable")
  }
}

///|
test "local user validation rejects duplicate and missing identities" {
  let user = try! auth_user(
    id="user-operator",
    username="operator",
    role=@continuity_forge.Role::Operator,
  )
  let store = try! @continuity_forge.LocalAuthStore::new().register_user(user~)
  try store.register_user(user~) catch {
    @continuity_forge.ModelError::DuplicateUser(value) =>
      inspect(value, content="user-operator")
    _ => fail("wrong error for duplicate user")
  } noraise {
    _ => fail("expected duplicate user validation")
  }
  try
    store.authorize(
      user_id="missing",
      permission=@continuity_forge.Permission::ReadProjects,
    )
  catch {
    @continuity_forge.ModelError::UserNotFound(value) =>
      inspect(value, content="missing")
    _ => fail("wrong error for missing user")
  } noraise {
    _ => fail("expected missing user validation")
  }
  try
    @continuity_forge.LocalUser::new(
      id="",
      username="operator",
      role=@continuity_forge.Role::Operator,
    )
  catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="user.id")
    _ => fail("wrong error for empty user id")
  } noraise {
    _ => fail("expected empty user id validation")
  }
}
