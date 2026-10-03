///|
fn playbook_asset(
  value~ : String,
) -> @continuity_forge.AssetRef raise @continuity_forge.ModelError {
  @continuity_forge.AssetRef::Service(@continuity_forge.ServiceId::new(value~))
}

///|
fn playbook_step(
  id~ : String,
  asset~ : @continuity_forge.AssetRef,
  owner~ : String,
  requires_approval~ : Bool,
  prerequisites~ : Array[String],
) -> @continuity_forge.RecoveryStep raise @continuity_forge.ModelError {
  @continuity_forge.RecoveryStep::new(
    id~,
    asset~,
    owner~,
    requires_approval~,
    prerequisites~,
  )
}

///|
test "playbook validates step references" {
  let api = try! playbook_asset(value="checkout-api")
  let database = try! playbook_asset(value="postgres-primary")
  let db_step = try! playbook_step(
    id="restore-db",
    asset=database,
    owner="database-team",
    requires_approval=false,
    prerequisites=[],
  )
  let api_step = try! playbook_step(
    id="restore-api",
    asset=api,
    owner="platform-team",
    requires_approval=false,
    prerequisites=["restore-db"],
  )
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="checkout-recovery",
    steps=[db_step, api_step],
  )
  assert_eq(playbook.steps.length(), 2)
  match playbook.status {
    @continuity_forge.PlaybookStatus::Draft => ()
    _ => fail("new playbook must be draft")
  }
  match playbook.steps[0].status {
    @continuity_forge.StepStatus::Pending => ()
    _ => fail("new step must be pending")
  }
}

///|
test "unfinished prerequisites block a dependent step" {
  let api = try! playbook_asset(value="checkout-api")
  let database = try! playbook_asset(value="postgres-primary")
  let db_step = try! playbook_step(
    id="restore-db",
    asset=database,
    owner="database-team",
    requires_approval=false,
    prerequisites=[],
  )
  let api_step = try! playbook_step(
    id="restore-api",
    asset=api,
    owner="platform-team",
    requires_approval=false,
    prerequisites=["restore-db"],
  )
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="checkout-recovery",
    steps=[db_step, api_step],
  )
  try playbook.begin_step(step_id="restore-api") catch {
    @continuity_forge.ModelError::StepBlocked(message) =>
      inspect(
        message,
        content="step restore-api waits for prerequisite restore-db",
      )
    _ => fail("wrong error for blocked step")
  } noraise {
    _ => fail("expected the dependent step to be blocked")
  }
}

///|
test "approval gates a step until explicit approval" {
  let database = try! playbook_asset(value="postgres-primary")
  let db_step = try! playbook_step(
    id="restore-db",
    asset=database,
    owner="database-team",
    requires_approval=true,
    prerequisites=[],
  )
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="database-recovery",
    steps=[db_step],
  )
  let waiting = try! playbook.begin_step(step_id="restore-db")
  match waiting.steps[0].status {
    @continuity_forge.StepStatus::AwaitingApproval => ()
    _ => fail("step must wait for approval")
  }
  try waiting.complete_step(step_id="restore-db") catch {
    @continuity_forge.ModelError::InvalidStepTransition(message) =>
      inspect(message, content="step restore-db is not in progress")
    _ => fail("wrong error before approval")
  } noraise {
    _ => fail("expected approval gate to block completion")
  }
  let approved = try! waiting.approve_step(step_id="restore-db")
  let completed = try! approved.complete_step(step_id="restore-db")
  match completed.status {
    @continuity_forge.PlaybookStatus::Completed => ()
    _ => fail("completed final step must complete the playbook")
  }
}

///|
test "steps without approval can progress and missing steps are reported" {
  let api = try! playbook_asset(value="checkout-api")
  let api_step = try! playbook_step(
    id="restore-api",
    asset=api,
    owner="platform-team",
    requires_approval=false,
    prerequisites=[],
  )
  let playbook = try! @continuity_forge.RecoveryPlaybook::new(
    id="api-recovery",
    steps=[api_step],
  )
  let running = try! playbook.begin_step(step_id="restore-api")
  match running.steps[0].status {
    @continuity_forge.StepStatus::InProgress => ()
    _ => fail("step should enter progress directly")
  }
  try running.begin_step(step_id="missing") catch {
    @continuity_forge.ModelError::StepNotFound(step_id) =>
      inspect(step_id, content="missing")
    _ => fail("wrong error for missing step")
  } noraise {
    _ => fail("expected a missing step error")
  }
}

///|
test "invalid playbook references are rejected" {
  let api = try! playbook_asset(value="checkout-api")
  let self_step = try! playbook_step(
    id="restore-api",
    asset=api,
    owner="platform-team",
    requires_approval=false,
    prerequisites=["restore-api"],
  )
  try
    @continuity_forge.RecoveryPlaybook::new(id="invalid-recovery", steps=[
      self_step,
    ])
  catch {
    @continuity_forge.ModelError::PlaybookValidation(message) =>
      inspect(message, content="step restore-api cannot depend on itself")
    _ => fail("wrong error for self prerequisite")
  } noraise {
    _ => fail("expected self prerequisite validation")
  }
}

///|
test "duplicate prerequisites are rejected" {
  let api = try! playbook_asset(value="checkout-api")
  let database = try! playbook_asset(value="postgres-primary")
  let db_step = try! playbook_step(
    id="restore-db",
    asset=database,
    owner="database-team",
    requires_approval=false,
    prerequisites=[],
  )
  let api_step = try! playbook_step(
    id="restore-api",
    asset=api,
    owner="platform-team",
    requires_approval=false,
    prerequisites=["restore-db", "restore-db"],
  )
  try
    @continuity_forge.RecoveryPlaybook::new(id="invalid-recovery", steps=[
      db_step, api_step,
    ])
  catch {
    @continuity_forge.ModelError::PlaybookValidation(message) =>
      inspect(
        message,
        content="duplicate prerequisite restore-db for step restore-api",
      )
    _ => fail("wrong error for duplicate prerequisite")
  } noraise {
    _ => fail("expected duplicate prerequisite validation")
  }
}
