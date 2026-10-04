///|
fn storage_project(
  id~ : String,
  name~ : String,
  owner~ : String,
) -> @continuity_forge.Project raise @continuity_forge.ModelError {
  @continuity_forge.Project::new(id~, name~, owner~)
}

///|
fn storage_event(
  sequence~ : Int,
  timestamp_minutes~ : Int,
  actor~ : String,
  action~ : @continuity_forge.AuditAction,
) -> @continuity_forge.AuditEvent raise @continuity_forge.ModelError {
  @continuity_forge.AuditEvent::new(
    sequence~,
    timestamp_minutes~,
    actor~,
    action~,
    step_id=None,
  )
}

///|
test "storage saves and updates projects" {
  let storage = @continuity_forge.ContinuityStorage::new()
  let project = try! storage_project(
    id="checkout",
    name="Checkout continuity",
    owner="commerce",
  )
  let saved = try! storage.save_project(project~)
  match saved.get_project(project_id="checkout") {
    Some(value) => assert_eq(value.owner, "commerce")
    None => fail("saved project must be readable")
  }
  let updated = try! storage_project(
    id="checkout",
    name="Checkout continuity",
    owner="resilience",
  )
  let replaced = try! saved.save_project(project=updated)
  assert_eq(replaced.list_projects().length(), 1)
  match replaced.get_project(project_id="checkout") {
    Some(value) => assert_eq(value.owner, "resilience")
    None => fail("updated project must be readable")
  }
}

///|
test "storage appends project audit timeline" {
  let storage = @continuity_forge.ContinuityStorage::new()
  let project = try! storage_project(
    id="checkout",
    name="Checkout continuity",
    owner="commerce",
  )
  let saved = try! storage.save_project(project~)
  let started = try! storage_event(
    sequence=1,
    timestamp_minutes=10,
    actor="operator",
    action=@continuity_forge.AuditAction::DrillStarted,
  )
  let completed = try! storage_event(
    sequence=2,
    timestamp_minutes=40,
    actor="operator",
    action=@continuity_forge.AuditAction::DrillFinished,
  )
  let with_start = try! saved.append_audit(
    record=try! @continuity_forge.AuditRecord::new(
      id="audit-1",
      project_id="checkout",
      event=started,
    ),
  )
  let with_finish = try! with_start.append_audit(
    record=try! @continuity_forge.AuditRecord::new(
      id="audit-2",
      project_id="checkout",
      event=completed,
    ),
  )
  let timeline = try! with_finish.audit_timeline(project_id="checkout")
  assert_eq(timeline.length(), 2)
  assert_eq(timeline[0].id, "audit-1")
  assert_eq(timeline[1].event.timestamp_minutes, 40)
}

///|
test "storage rejects unknown duplicate and out of order audits" {
  let storage = @continuity_forge.ContinuityStorage::new()
  let event = try! storage_event(
    sequence=1,
    timestamp_minutes=10,
    actor="operator",
    action=@continuity_forge.AuditAction::DrillStarted,
  )
  let record = try! @continuity_forge.AuditRecord::new(
    id="audit-1",
    project_id="missing",
    event~,
  )
  try storage.append_audit(record~) catch {
    @continuity_forge.ModelError::ProjectNotFound(project_id) =>
      inspect(project_id, content="missing")
    _ => fail("wrong error for unknown project")
  } noraise {
    _ => fail("expected unknown project validation")
  }

  let project = try! storage_project(
    id="checkout",
    name="Checkout continuity",
    owner="commerce",
  )
  let saved = try! storage.save_project(project~)
  let with_record = try! saved.append_audit(record={
    id: "audit-1",
    project_id: "checkout",
    event,
  })
  try
    with_record.append_audit(record={
      id: "audit-1",
      project_id: "checkout",
      event,
    })
  catch {
    @continuity_forge.ModelError::DuplicateAuditRecord(record_id) =>
      inspect(record_id, content="audit-1")
    _ => fail("wrong error for duplicate audit")
  } noraise {
    _ => fail("expected duplicate audit validation")
  }
  let earlier = try! storage_event(
    sequence=2,
    timestamp_minutes=5,
    actor="operator",
    action=@continuity_forge.AuditAction::StepStarted,
  )
  try
    with_record.append_audit(record={
      id: "audit-2",
      project_id: "checkout",
      event: earlier,
    })
  catch {
    @continuity_forge.ModelError::StorageValidation(message) =>
      inspect(
        message,
        content="audit records must be appended in timestamp order",
      )
    _ => fail("wrong error for out of order audit")
  } noraise {
    _ => fail("expected chronology validation")
  }
}
