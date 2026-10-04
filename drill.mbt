///|
/// Lifecycle states for a continuity exercise.
pub(all) enum DrillStatus {
  Planned
  Running
  Completed
}

///|
/// Actions captured in a drill audit timeline.
pub(all) enum AuditAction {
  DrillStarted
  StepStarted
  StepApproved
  StepCompleted
  DrillFinished
}

///|
/// One immutable entry in a drill's ordered audit timeline.
pub(all) struct AuditEvent {
  sequence : Int
  timestamp_minutes : Int
  actor : String
  action : AuditAction
  step_id : String?
}

///|
/// Creates a validated audit event.
pub fn AuditEvent::new(
  sequence~ : Int,
  timestamp_minutes~ : Int,
  actor~ : String,
  action~ : AuditAction,
  step_id~ : String?,
) -> AuditEvent raise ModelError {
  if sequence < 1 {
    raise ModelError::DrillValidation("audit sequence must be positive")
  }
  if timestamp_minutes < 0 {
    raise ModelError::InvalidDuration(
      "audit.timestamp_minutes must be non-negative",
    )
  }
  if actor == "" {
    raise ModelError::EmptyField("drill.actor")
  }
  match step_id {
    Some(value) =>
      if value == "" {
        raise ModelError::EmptyField("drill.step_id")
      }
    None => ()
  }
  { sequence, timestamp_minutes, actor, action, step_id, }
}

///|
/// A recovery playbook execution with a reproducible audit timeline.
pub(all) struct RecoveryDrill {
  id : String
  playbook : RecoveryPlaybook
  status : DrillStatus
  timeline : Array[AuditEvent]
}

///|
/// Creates a planned drill with an empty audit timeline.
pub fn RecoveryDrill::new(
  id~ : String,
  playbook~ : RecoveryPlaybook,
) -> RecoveryDrill raise ModelError {
  if id == "" {
    raise ModelError::EmptyField("drill.id")
  }
  { id, playbook, status: Planned, timeline: [], }
}

///|
fn RecoveryDrill::append_event(
  self : RecoveryDrill,
  playbook~ : RecoveryPlaybook,
  status~ : DrillStatus,
  actor~ : String,
  timestamp_minutes~ : Int,
  action~ : AuditAction,
  step_id~ : String?,
) -> RecoveryDrill raise ModelError {
  if self.timeline.length() > 0 {
    let previous = self.timeline[self.timeline.length() - 1]
    if timestamp_minutes < previous.timestamp_minutes {
      raise ModelError::DrillValidation(
        "audit timestamp must not move backwards",
      )
    }
  }
  let event = AuditEvent::new(
    sequence=self.timeline.length() + 1,
    timestamp_minutes~,
    actor~,
    action~,
    step_id~,
  )
  let timeline : Array[AuditEvent] = []
  for existing in self.timeline {
    timeline.push(existing)
  }
  timeline.push(event)
  { id: self.id, playbook, status, timeline, }
}

///|
/// Returns a copy of the ordered audit entries for reporting.
pub fn RecoveryDrill::audit_timeline(self : RecoveryDrill) -> Array[AuditEvent] {
  let timeline : Array[AuditEvent] = []
  for event in self.timeline {
    timeline.push(event)
  }
  timeline
}

///|
/// Starts a planned drill and records the operator and logical timestamp.
pub fn RecoveryDrill::start(
  self : RecoveryDrill,
  actor~ : String,
  timestamp_minutes~ : Int,
) -> RecoveryDrill raise ModelError {
  match self.status {
    Planned =>
      self.append_event(
        playbook=self.playbook,
        status=Running,
        actor~,
        timestamp_minutes~,
        action=DrillStarted,
        step_id=None,
      )
    Running =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} is already running",
      )
    Completed =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has already completed",
      )
  }
}

///|
/// Begins one playbook step and records the step start.
pub fn RecoveryDrill::begin_step(
  self : RecoveryDrill,
  step_id~ : String,
  actor~ : String,
  timestamp_minutes~ : Int,
) -> RecoveryDrill raise ModelError {
  match self.status {
    Running => {
      let playbook = self.playbook.begin_step(step_id~)
      self.append_event(
        playbook~,
        status=self.status,
        actor~,
        timestamp_minutes~,
        action=StepStarted,
        step_id=Some(step_id),
      )
    }
    Planned =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has not started",
      )
    Completed =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has already completed",
      )
  }
}

///|
/// Approves a step waiting at its manual approval gate.
pub fn RecoveryDrill::approve_step(
  self : RecoveryDrill,
  step_id~ : String,
  actor~ : String,
  timestamp_minutes~ : Int,
) -> RecoveryDrill raise ModelError {
  match self.status {
    Running => {
      let playbook = self.playbook.approve_step(step_id~)
      self.append_event(
        playbook~,
        status=self.status,
        actor~,
        timestamp_minutes~,
        action=StepApproved,
        step_id=Some(step_id),
      )
    }
    Planned =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has not started",
      )
    Completed =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has already completed",
      )
  }
}

///|
/// Completes one in-progress playbook step and records the result.
pub fn RecoveryDrill::complete_step(
  self : RecoveryDrill,
  step_id~ : String,
  actor~ : String,
  timestamp_minutes~ : Int,
) -> RecoveryDrill raise ModelError {
  match self.status {
    Running => {
      let playbook = self.playbook.complete_step(step_id~)
      self.append_event(
        playbook~,
        status=self.status,
        actor~,
        timestamp_minutes~,
        action=StepCompleted,
        step_id=Some(step_id),
      )
    }
    Planned =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has not started",
      )
    Completed =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has already completed",
      )
  }
}

///|
/// Finishes a drill after every playbook step has succeeded.
pub fn RecoveryDrill::finish(
  self : RecoveryDrill,
  actor~ : String,
  timestamp_minutes~ : Int,
) -> RecoveryDrill raise ModelError {
  match self.status {
    Running =>
      match self.playbook.status {
        PlaybookStatus::Completed =>
          self.append_event(
            playbook=self.playbook,
            status=Completed,
            actor~,
            timestamp_minutes~,
            action=DrillFinished,
            step_id=None,
          )
        _ =>
          raise ModelError::DrillValidation(
            "cannot finish drill before all playbook steps succeed",
          )
      }
    Planned =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has not started",
      )
    Completed =>
      raise ModelError::InvalidDrillTransition(
        "drill \{self.id} has already completed",
      )
  }
}
