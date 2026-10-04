///|
fn drill_asset(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(@continuity_forge.ServiceId::new(value~))
}

///|
fn drill_step(
  id~ : String,
  asset~ : @continuity_forge.AssetRef,
  requires_approval~ : Bool,
) -> @continuity_forge.RecoveryStep raise @continuity_forge.ModelError {
  @continuity_forge.RecoveryStep::new(
    id~,
    asset~,
    owner="exercise-operator",
    requires_approval~,
    prerequisites=[],
  )
}

///|
test "drill records an ordered audit timeline" {
  let asset = try! drill_asset(value="checkout-api")
  let step = try! drill_step(id="restore-api", asset~, requires_approval=true)
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="checkout-recovery",
    steps=[step],
  )
  let drill = try! @continuity_forge.RecoveryDrill::new(
    id="checkout-drill",
    playbook~,
  )
  let started = try! drill.start(actor="operator", timestamp_minutes=10)
  let waiting = try! started.begin_step(
    step_id="restore-api",
    actor="operator",
    timestamp_minutes=20,
  )
  let approved = try! waiting.approve_step(
    step_id="restore-api",
    actor="approver",
    timestamp_minutes=25,
  )
  let running = try! approved.complete_step(
    step_id="restore-api",
    actor="operator",
    timestamp_minutes=40,
  )
  let finished = try! running.finish(actor="operator", timestamp_minutes=45)
  match finished.status {
    @continuity_forge.DrillStatus::Completed => ()
    _ => fail("finished drill must be completed")
  }
  let timeline = finished.audit_timeline()
  assert_eq(timeline.length(), 5)
  assert_eq(timeline[0].sequence, 1)
  assert_eq(timeline[4].sequence, 5)
  assert_eq(timeline[0].timestamp_minutes, 10)
  assert_eq(timeline[4].timestamp_minutes, 45)
  match timeline[0].action {
    @continuity_forge.AuditAction::DrillStarted => ()
    _ => fail("first audit action must start the drill")
  }
  match timeline[2].action {
    @continuity_forge.AuditAction::StepApproved => ()
    _ => fail("approval must be recorded")
  }
  match timeline[2].step_id {
    Some(step_id) => inspect(step_id, content="restore-api")
    None => fail("step audit action must identify the step")
  }
}

///|
test "drill requires all steps before finishing" {
  let asset = try! drill_asset(value="checkout-api")
  let step = try! drill_step(id="restore-api", asset~, requires_approval=false)
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="checkout-recovery",
    steps=[step],
  )
  let drill = try! @continuity_forge.RecoveryDrill::new(
    id="checkout-drill",
    playbook~,
  )
  let started = try! drill.start(actor="operator", timestamp_minutes=10)
  try started.finish(actor="operator", timestamp_minutes=20) catch {
    @continuity_forge.ModelError::DrillValidation(message) =>
      inspect(
        message,
        content="cannot finish drill before all playbook steps succeed",
      )
    _ => fail("wrong error for unfinished drill")
  } noraise {
    _ => fail("expected unfinished drill to reject finish")
  }
}

///|
test "drill rejects invalid actors and backwards timestamps" {
  let asset = try! drill_asset(value="checkout-api")
  let step = try! drill_step(id="restore-api", asset~, requires_approval=false)
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="checkout-recovery",
    steps=[step],
  )
  let drill = try! @continuity_forge.RecoveryDrill::new(
    id="checkout-drill",
    playbook~,
  )
  try drill.start(actor="", timestamp_minutes=10) catch {
    @continuity_forge.ModelError::EmptyField(field) =>
      inspect(field, content="drill.actor")
    _ => fail("wrong error for empty actor")
  } noraise {
    _ => fail("expected empty actor validation")
  }
  let started = try! drill.start(actor="operator", timestamp_minutes=10)
  try
    started.begin_step(
      step_id="restore-api",
      actor="operator",
      timestamp_minutes=9,
    )
  catch {
    @continuity_forge.ModelError::DrillValidation(message) =>
      inspect(message, content="audit timestamp must not move backwards")
    _ => fail("wrong error for backwards timestamp")
  } noraise {
    _ => fail("expected backwards timestamp validation")
  }
}
