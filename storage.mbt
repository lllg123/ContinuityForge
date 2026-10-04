///|
/// A continuity project stored independently from its execution records.
pub(all) struct Project {
  id : String
  name : String
  owner : String
}

///|
/// Creates a project with the metadata required by the storage layer.
pub fn Project::new(
  id~ : String,
  name~ : String,
  owner~ : String,
) -> Project raise ModelError {
  if id == "" {
    raise ModelError::EmptyField("project.id")
  }
  if name == "" {
    raise ModelError::EmptyField("project.name")
  }
  if owner == "" {
    raise ModelError::EmptyField("project.owner")
  }
  { id, name, owner, }
}

///|
/// A persisted audit event associated with one project.
pub(all) struct AuditRecord {
  id : String
  project_id : String
  event : AuditEvent
}

///|
/// Creates an audit record and revalidates its event payload.
pub fn AuditRecord::new(
  id~ : String,
  project_id~ : String,
  event~ : AuditEvent,
) -> AuditRecord raise ModelError {
  if id == "" {
    raise ModelError::EmptyField("audit_record.id")
  }
  if project_id == "" {
    raise ModelError::EmptyField("audit_record.project_id")
  }
  let valid_event = AuditEvent::new(
    sequence=event.sequence,
    timestamp_minutes=event.timestamp_minutes,
    actor=event.actor,
    action=event.action,
    step_id=event.step_id,
  )
  { id, project_id, event: valid_event, }
}

///|
/// An immutable storage snapshot for projects and their audit records.
pub(all) struct ContinuityStorage {
  projects : Array[Project]
  audits : Array[AuditRecord]
}

///|
/// Creates an empty storage snapshot.
pub fn ContinuityStorage::new() -> ContinuityStorage {
  { projects: [], audits: [], }
}

///|
fn project_index(projects : Array[Project], id : String) -> Int? {
  let mut result : Int? = None
  for i, project in projects {
    if result is None && project.id == id {
      result = Some(i)
    }
  }
  result
}

///|
fn audit_index(audits : Array[AuditRecord], id : String) -> Int? {
  let mut result : Int? = None
  for i, audit in audits {
    if result is None && audit.id == id {
      result = Some(i)
    }
  }
  result
}

///|
fn copy_projects(projects : Array[Project]) -> Array[Project] {
  let result : Array[Project] = []
  for project in projects {
    result.push(project)
  }
  result
}

///|
fn copy_audits(audits : Array[AuditRecord]) -> Array[AuditRecord] {
  let result : Array[AuditRecord] = []
  for audit in audits {
    result.push(audit)
  }
  result
}

///|
/// Saves a project, replacing the previous version with the same ID.
pub fn ContinuityStorage::save_project(
  self : ContinuityStorage,
  project~ : Project,
) -> ContinuityStorage raise ModelError {
  let valid_project = Project::new(
    id=project.id,
    name=project.name,
    owner=project.owner,
  )
  let projects = copy_projects(self.projects)
  match project_index(projects, valid_project.id) {
    Some(index) => projects[index] = valid_project
    None => projects.push(valid_project)
  }
  { projects, audits: copy_audits(self.audits), }
}

///|
/// Returns a stored project when its ID exists.
pub fn ContinuityStorage::get_project(
  self : ContinuityStorage,
  project_id~ : String,
) -> Project? {
  match project_index(self.projects, project_id) {
    Some(index) => Some(self.projects[index])
    None => None
  }
}

///|
/// Returns all stored projects in insertion order.
pub fn ContinuityStorage::list_projects(
  self : ContinuityStorage,
) -> Array[Project] {
  copy_projects(self.projects)
}

///|
/// Appends an audit record after validating project ownership and chronology.
pub fn ContinuityStorage::append_audit(
  self : ContinuityStorage,
  record~ : AuditRecord,
) -> ContinuityStorage raise ModelError {
  let valid_record = AuditRecord::new(
    id=record.id,
    project_id=record.project_id,
    event=record.event,
  )
  if project_index(self.projects, valid_record.project_id) is None {
    raise ModelError::ProjectNotFound(valid_record.project_id)
  }
  if audit_index(self.audits, valid_record.id) is Some(_) {
    raise ModelError::DuplicateAuditRecord(valid_record.id)
  }
  let mut previous_timestamp : Int? = None
  for existing in self.audits {
    if existing.project_id == valid_record.project_id {
      previous_timestamp = Some(existing.event.timestamp_minutes)
    }
  }
  match previous_timestamp {
    Some(previous) =>
      if valid_record.event.timestamp_minutes < previous {
        raise ModelError::StorageValidation(
          "audit records must be appended in timestamp order",
        )
      }
    None => ()
  }
  let audits = copy_audits(self.audits)
  audits.push(valid_record)
  { projects: copy_projects(self.projects), audits, }
}

///|
/// Returns a project's audit records in append order.
pub fn ContinuityStorage::audit_timeline(
  self : ContinuityStorage,
  project_id~ : String,
) -> Array[AuditRecord] raise ModelError {
  if project_index(self.projects, project_id) is None {
    raise ModelError::ProjectNotFound(project_id)
  }
  let result : Array[AuditRecord] = []
  for audit in self.audits {
    if audit.project_id == project_id {
      result.push(audit)
    }
  }
  result
}
