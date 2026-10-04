///|
/// Roles available to local continuity users.
pub(all) enum Role {
  Viewer
  Operator
  Approver
  Administrator
}

///|
/// Domain permissions checked by the local authorization store.
pub(all) enum Permission {
  ReadProjects
  ReadAudit
  RunDrills
  ApproveRecovery
  ManageUsers
}

///|
/// Returns whether a role includes one domain permission.
pub fn Role::allows(self : Role, permission : Permission) -> Bool {
  match self {
    Viewer =>
      match permission {
        ReadProjects => true
        ReadAudit => true
        RunDrills => false
        ApproveRecovery => false
        ManageUsers => false
      }
    Operator =>
      match permission {
        ReadProjects => true
        ReadAudit => true
        RunDrills => true
        ApproveRecovery => false
        ManageUsers => false
      }
    Approver =>
      match permission {
        ReadProjects => true
        ReadAudit => true
        RunDrills => true
        ApproveRecovery => true
        ManageUsers => false
      }
    Administrator => true
  }
}

///|
fn permission_label(permission : Permission) -> String {
  match permission {
    ReadProjects => "read_projects"
    ReadAudit => "read_audit"
    RunDrills => "run_drills"
    ApproveRecovery => "approve_recovery"
    ManageUsers => "manage_users"
  }
}

///|
/// A local user identity and its assigned role.
///
/// The core model stores no password or credential material.
pub(all) struct LocalUser {
  id : String
  username : String
  role : Role
  active : Bool
}

///|
/// Creates an active local user.
pub fn LocalUser::new(
  id~ : String,
  username~ : String,
  role~ : Role,
) -> LocalUser raise ModelError {
  if id == "" {
    raise ModelError::EmptyField("user.id")
  }
  if username == "" {
    raise ModelError::EmptyField("user.username")
  }
  { id, username, role, active: true, }
}

///|
fn LocalUser::with_active(self : LocalUser, active : Bool) -> LocalUser {
  { id: self.id, username: self.username, role: self.role, active, }
}

///|
/// An immutable local user registry used by domain authorization checks.
pub(all) struct LocalAuthStore {
  users : Array[LocalUser]
}

///|
/// Creates an empty local authorization store.
pub fn LocalAuthStore::new() -> LocalAuthStore {
  { users: [], }
}

///|
fn user_index(users : Array[LocalUser], user_id : String) -> Int? {
  let mut result : Int? = None
  for i, user in users {
    if result is None && user.id == user_id {
      result = Some(i)
    }
  }
  result
}

///|
fn username_index(users : Array[LocalUser], username : String) -> Int? {
  let mut result : Int? = None
  for i, user in users {
    if result is None && user.username == username {
      result = Some(i)
    }
  }
  result
}

///|
fn copy_users(users : Array[LocalUser]) -> Array[LocalUser] {
  let result : Array[LocalUser] = []
  for user in users {
    result.push(user)
  }
  result
}

///|
fn replace_user(
  users : Array[LocalUser],
  index : Int,
  user : LocalUser,
) -> Array[LocalUser] {
  let result = copy_users(users)
  result[index] = user
  result
}

///|
/// Registers a user and rejects duplicate IDs or usernames.
pub fn LocalAuthStore::register_user(
  self : LocalAuthStore,
  user~ : LocalUser,
) -> LocalAuthStore raise ModelError {
  let valid_user = LocalUser::new(
    id=user.id,
    username=user.username,
    role=user.role,
  )
  if user_index(self.users, valid_user.id) is Some(_) {
    raise ModelError::DuplicateUser(valid_user.id)
  }
  if username_index(self.users, valid_user.username) is Some(_) {
    raise ModelError::DuplicateUser(valid_user.username)
  }
  let users = copy_users(self.users)
  users.push(valid_user)
  { users, }
}

///|
/// Returns a local user when its ID exists.
pub fn LocalAuthStore::get_user(
  self : LocalAuthStore,
  user_id~ : String,
) -> LocalUser? {
  match user_index(self.users, user_id) {
    Some(index) => Some(self.users[index])
    None => None
  }
}

///|
/// Returns all local users in registration order.
pub fn LocalAuthStore::list_users(self : LocalAuthStore) -> Array[LocalUser] {
  copy_users(self.users)
}

///|
/// Deactivates a local user without deleting its audit-relevant identity.
pub fn LocalAuthStore::deactivate_user(
  self : LocalAuthStore,
  user_id~ : String,
) -> LocalAuthStore raise ModelError {
  let index = match user_index(self.users, user_id) {
    Some(index) => index
    None => raise ModelError::UserNotFound(user_id)
  }
  {
    users: replace_user(self.users, index, self.users[index].with_active(false)),
  }
}

///|
/// Reactivates a previously deactivated local user.
pub fn LocalAuthStore::activate_user(
  self : LocalAuthStore,
  user_id~ : String,
) -> LocalAuthStore raise ModelError {
  let index = match user_index(self.users, user_id) {
    Some(index) => index
    None => raise ModelError::UserNotFound(user_id)
  }
  {
    users: replace_user(self.users, index, self.users[index].with_active(true)),
  }
}

///|
/// Returns whether an active user has a permission.
pub fn LocalAuthStore::can(
  self : LocalAuthStore,
  user_id~ : String,
  permission~ : Permission,
) -> Bool {
  match user_index(self.users, user_id) {
    Some(index) => {
      let user = self.users[index]
      user.active && user.role.allows(permission)
    }
    None => false
  }
}

///|
/// Requires an active user to hold a permission.
pub fn LocalAuthStore::authorize(
  self : LocalAuthStore,
  user_id~ : String,
  permission~ : Permission,
) -> Unit raise ModelError {
  let user = match user_index(self.users, user_id) {
    Some(index) => self.users[index]
    None => raise ModelError::UserNotFound(user_id)
  }
  if !user.active {
    raise ModelError::AccessDenied("user \{user.username} is inactive")
  }
  if !user.role.allows(permission) {
    raise ModelError::AccessDenied(
      "user \{user.username} lacks \{permission_label(permission)}",
    )
  }
}
