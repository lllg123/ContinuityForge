///|
/// Units supported by business continuity time targets.
pub(all) enum TimeUnit {
  Minutes
  Hours
  Days
}

///|
/// A non-negative duration with an explicit unit.
pub(all) struct TimeSpan {
  amount : Int
  unit : TimeUnit
}

///|
/// Creates a duration and rejects negative amounts.
pub fn TimeSpan::new(
  amount~ : Int,
  unit~ : TimeUnit,
) -> TimeSpan raise ModelError {
  if amount < 0 {
    raise ModelError::InvalidDuration("duration.amount must be non-negative")
  }
  { amount, unit, }
}

///|
/// Converts a duration to minutes for comparing recovery targets.
pub fn TimeSpan::as_minutes(self : TimeSpan) -> Int {
  match self.unit {
    Minutes => self.amount
    Hours => self.amount * 60
    Days => self.amount * 24 * 60
  }
}

///|
/// Business impact levels derived from an impact score.
pub(all) enum ImpactLevel {
  Low
  Medium
  High
  Critical
} derive(Debug, Eq)

///|
/// Keep derived trait methods explicit for the current MoonBit toolchain.
pub extend ImpactLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ImpactLevel with Eq::{not_equal, equal}

///|
/// Applies the platform's inclusive score bands to an impact score.
pub fn ImpactLevel::from_score(score : Int) -> ImpactLevel raise ModelError {
  if score < 0 || score > 100 {
    raise ModelError::InvalidImpactScore(
      "impact_score must be between 0 and 100",
    )
  }
  if score < 25 {
    Low
  } else if score < 50 {
    Medium
  } else if score < 75 {
    High
  } else {
    Critical
  }
}

///|
fn validate_assessment_duration(
  field : String,
  duration : TimeSpan,
  positive : Bool,
) -> Unit raise ModelError {
  if duration.amount < 0 {
    raise ModelError::InvalidDuration("\{field}.amount must be non-negative")
  }
  if positive && duration.amount == 0 {
    raise ModelError::InvalidDuration("\{field} must be positive")
  }
}

///|
/// Business impact targets and their derived criticality for one service.
pub(all) struct BusinessImpactAssessment {
  service_id : ServiceId
  impact_score : Int
  impact_level : ImpactLevel
  rto : TimeSpan
  rpo : TimeSpan
  max_tolerable_downtime : TimeSpan
}

///|
/// Creates a validated business impact assessment.
pub fn BusinessImpactAssessment::new(
  service_id~ : ServiceId,
  impact_score~ : Int,
  rto~ : TimeSpan,
  rpo~ : TimeSpan,
  max_tolerable_downtime~ : TimeSpan,
) -> BusinessImpactAssessment raise ModelError {
  if service_id.value == "" {
    raise ModelError::EmptyField("service_id")
  }
  let impact_level = ImpactLevel::from_score(impact_score)
  validate_assessment_duration("rto", rto, false)
  validate_assessment_duration("rpo", rpo, false)
  validate_assessment_duration(
    "max_tolerable_downtime", max_tolerable_downtime, true,
  )
  if rto.as_minutes() > max_tolerable_downtime.as_minutes() {
    raise ModelError::InvalidBia("rto must not exceed max_tolerable_downtime")
  }
  if rpo.as_minutes() > max_tolerable_downtime.as_minutes() {
    raise ModelError::InvalidBia("rpo must not exceed max_tolerable_downtime")
  }
  { service_id, impact_score, impact_level, rto, rpo, max_tolerable_downtime, }
}
