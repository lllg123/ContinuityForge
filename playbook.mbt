///|
/// Lifecycle states for one recovery step.
pub(all) enum StepStatus {
  Pending
  AwaitingApproval
  InProgress
  Succeeded
}

///|
/// Lifecycle states for a recovery playbook.
pub(all) enum PlaybookStatus {
  Draft
  Active
  Completed
}

///|
/// A human-owned recovery action and its step prerequisites.
pub(all) struct RecoveryStep {
  id : String
  asset : AssetRef
  owner : String
  requires_approval : Bool
  prerequisites : Array[String]
  status : StepStatus
}

///|
/// Creates a pending recovery step.
pub fn RecoveryStep::new(
  id~ : String,
  asset~ : AssetRef,
  owner~ : String,
  requires_approval~ : Bool,
  prerequisites~ : Array[String],
) -> RecoveryStep raise ModelError {
  if id == "" {
    raise ModelError::EmptyField("playbook.step_id")
  }
  if owner == "" {
    raise ModelError::EmptyField("playbook.owner")
  }
  { id, asset, owner, requires_approval, prerequisites, status: Pending, }
}

///|
fn RecoveryStep::with_status(
  self : RecoveryStep,
  status : StepStatus,
) -> RecoveryStep {
  {
    id: self.id,
    asset: self.asset,
    owner: self.owner,
    requires_approval: self.requires_approval,
    prerequisites: self.prerequisites,
    status,
  }
}

///|
/// A validated collection of recovery steps with a lifecycle status.
pub(all) struct RecoveryPlaybook {
  id : String
  steps : Array[RecoveryStep]
  status : PlaybookStatus
}

///|
fn step_index(steps : Array[RecoveryStep], id : String) -> Int? {
  let mut result : Int? = None
  for i, step in steps {
    if result is None && step.id == id {
      result = Some(i)
    }
  }
  result
}

///|
fn validate_step_references(
  steps : Array[RecoveryStep],
) -> Unit raise ModelError {
  for step in steps {
    for prerequisite_index, prerequisite in step.prerequisites {
      if prerequisite == step.id {
        raise ModelError::PlaybookValidation(
          "step \{step.id} cannot depend on itself",
        )
      }
      if step_index(steps, prerequisite) is None {
        raise ModelError::PlaybookValidation(
          "missing prerequisite \{prerequisite} for step \{step.id}",
        )
      }
      for earlier_index in 0..<prerequisite_index {
        if prerequisite == step.prerequisites[earlier_index] {
          raise ModelError::PlaybookValidation(
            "duplicate prerequisite \{prerequisite} for step \{step.id}",
          )
        }
      }
    }
  }
}

///|
/// Creates a draft playbook and validates all step references.
pub fn RecoveryPlaybook::new(
  id~ : String,
  steps~ : Array[RecoveryStep],
) -> RecoveryPlaybook raise ModelError {
  if id == "" {
    raise ModelError::EmptyField("playbook.id")
  }
  if steps.length() == 0 {
    raise ModelError::EmptyField("playbook.steps")
  }
  for i in 0..<steps.length() {
    for j in 0..<i {
      if steps[i].id == steps[j].id {
        raise ModelError::PlaybookValidation(
          "duplicate step id: \{steps[i].id}",
        )
      }
    }
  }
  validate_step_references(steps)
  { id, steps, status: Draft, }
}

///|
fn replace_step_status(
  steps : Array[RecoveryStep],
  index : Int,
  status : StepStatus,
) -> Array[RecoveryStep] {
  let updated : Array[RecoveryStep] = []
  for i, step in steps {
    if i == index {
      updated.push(step.with_status(status))
    } else {
      updated.push(step)
    }
  }
  updated
}

///|
fn first_unfinished_prerequisite(
  step : RecoveryStep,
  steps : Array[RecoveryStep],
) -> String? {
  let mut blocker : String? = None
  for prerequisite in step.prerequisites {
    match step_index(steps, prerequisite) {
      Some(index) =>
        match steps[index].status {
          Succeeded => ()
          _ => if blocker is None { blocker = Some(prerequisite) }
        }
      None => if blocker is None { blocker = Some(prerequisite) }
    }
  }
  blocker
}

///|
fn status_after_update(steps : Array[RecoveryStep]) -> PlaybookStatus {
  let mut all_succeeded = true
  for step in steps {
    match step.status {
      Succeeded => ()
      _ => all_succeeded = false
    }
  }
  if all_succeeded {
    Completed
  } else {
    Active
  }
}

///|
/// Moves a step to execution or to its approval gate.
pub fn RecoveryPlaybook::begin_step(
  self : RecoveryPlaybook,
  step_id~ : String,
) -> RecoveryPlaybook raise ModelError {
  let index = match step_index(self.steps, step_id) {
    Some(index) => index
    None => raise ModelError::StepNotFound(step_id)
  }
  let step = self.steps[index]
  match step.status {
    Pending =>
      match first_unfinished_prerequisite(step, self.steps) {
        Some(prerequisite) =>
          raise ModelError::StepBlocked(
            "step \{step.id} waits for prerequisite \{prerequisite}",
          )
        None => {
          let next_status = if step.requires_approval {
            AwaitingApproval
          } else {
            InProgress
          }
          let updated = replace_step_status(self.steps, index, next_status)
          { id: self.id, steps: updated, status: Active, }
        }
      }
    AwaitingApproval =>
      raise ModelError::InvalidStepTransition(
        "step \{step.id} is awaiting approval",
      )
    InProgress =>
      raise ModelError::InvalidStepTransition(
        "step \{step.id} is already in progress",
      )
    Succeeded =>
      raise ModelError::InvalidStepTransition(
        "step \{step.id} has already succeeded",
      )
  }
}

///|
/// Approves a step that is waiting at its manual approval gate.
pub fn RecoveryPlaybook::approve_step(
  self : RecoveryPlaybook,
  step_id~ : String,
) -> RecoveryPlaybook raise ModelError {
  let index = match step_index(self.steps, step_id) {
    Some(index) => index
    None => raise ModelError::StepNotFound(step_id)
  }
  let step = self.steps[index]
  match step.status {
    AwaitingApproval => {
      let updated = replace_step_status(self.steps, index, InProgress)
      { id: self.id, steps: updated, status: Active, }
    }
    _ =>
      raise ModelError::InvalidStepTransition(
        "step \{step.id} is not awaiting approval",
      )
  }
}

///|
/// Marks an in-progress step as successfully completed.
pub fn RecoveryPlaybook::complete_step(
  self : RecoveryPlaybook,
  step_id~ : String,
) -> RecoveryPlaybook raise ModelError {
  let index = match step_index(self.steps, step_id) {
    Some(index) => index
    None => raise ModelError::StepNotFound(step_id)
  }
  let step = self.steps[index]
  match step.status {
    InProgress => {
      let updated = replace_step_status(self.steps, index, Succeeded)
      { id: self.id, steps: updated, status: status_after_update(updated), }
    }
    _ =>
      raise ModelError::InvalidStepTransition(
        "step \{step.id} is not in progress",
      )
  }
}
