///|
fn bia_service_id() -> @continuity_forge.ServiceId raise @continuity_forge.ModelError {
  @continuity_forge.ServiceId::new(value="checkout")
}

///|
fn minutes(
  amount~ : Int,
) -> @continuity_forge.TimeSpan raise @continuity_forge.ModelError {
  @continuity_forge.TimeSpan::new(
    amount~,
    unit=@continuity_forge.TimeUnit::Minutes,
  )
}

///|
test "time units convert to minutes" {
  let hour = try! @continuity_forge.TimeSpan::new(
    amount=2,
    unit=@continuity_forge.TimeUnit::Hours,
  )
  let day = try! @continuity_forge.TimeSpan::new(
    amount=1,
    unit=@continuity_forge.TimeUnit::Days,
  )
  assert_eq(hour.as_minutes(), 120)
  assert_eq(day.as_minutes(), 1440)
}

///|
test "impact score bands derive the expected level" {
  assert_eq(
    try! @continuity_forge.ImpactLevel::from_score(0),
    @continuity_forge.ImpactLevel::Low,
  )
  assert_eq(
    try! @continuity_forge.ImpactLevel::from_score(25),
    @continuity_forge.ImpactLevel::Medium,
  )
  assert_eq(
    try! @continuity_forge.ImpactLevel::from_score(50),
    @continuity_forge.ImpactLevel::High,
  )
  assert_eq(
    try! @continuity_forge.ImpactLevel::from_score(75),
    @continuity_forge.ImpactLevel::Critical,
  )
}

///|
test "a valid assessment keeps mixed target units" {
  let assessment = try! @continuity_forge.BusinessImpactAssessment::new(
    service_id=try! bia_service_id(),
    impact_score=82,
    rto=try! minutes(amount=90),
    rpo=try! @continuity_forge.TimeSpan::new(
      amount=1,
      unit=@continuity_forge.TimeUnit::Hours,
    ),
    max_tolerable_downtime=try! @continuity_forge.TimeSpan::new(
      amount=2,
      unit=@continuity_forge.TimeUnit::Hours,
    ),
  )
  assert_eq(assessment.service_id.value, "checkout")
  assert_eq(assessment.impact_score, 82)
  assert_eq(assessment.impact_level, @continuity_forge.ImpactLevel::Critical)
  assert_eq(assessment.rto.as_minutes(), 90)
  assert_eq(assessment.rpo.as_minutes(), 60)
}

///|
test "invalid scores and durations identify their fields" {
  try @continuity_forge.ImpactLevel::from_score(101) catch {
    @continuity_forge.ModelError::InvalidImpactScore(message) =>
      inspect(message, content="impact_score must be between 0 and 100")
    _ => fail("wrong error for invalid impact score")
  } noraise {
    _ => fail("expected an invalid impact score error")
  }
  try
    @continuity_forge.TimeSpan::new(
      amount=-1,
      unit=@continuity_forge.TimeUnit::Minutes,
    )
  catch {
    @continuity_forge.ModelError::InvalidDuration(message) =>
      inspect(message, content="duration.amount must be non-negative")
    _ => fail("wrong error for negative duration")
  } noraise {
    _ => fail("expected a negative duration error")
  }
}

///|
test "recovery targets cannot exceed maximum tolerable downtime" {
  let service_id = try! bia_service_id()
  let rto = try! minutes(amount=181)
  let rpo = try! minutes(amount=30)
  let mtd = try! @continuity_forge.TimeSpan::new(
    amount=3,
    unit=@continuity_forge.TimeUnit::Hours,
  )
  try
    @continuity_forge.BusinessImpactAssessment::new(
      service_id~,
      impact_score=60,
      rto~,
      rpo~,
      max_tolerable_downtime=mtd,
    )
  catch {
    @continuity_forge.ModelError::InvalidBia(message) =>
      inspect(message, content="rto must not exceed max_tolerable_downtime")
    _ => fail("wrong error for rto ordering")
  } noraise {
    _ => fail("expected an invalid rto ordering")
  }

  let zero_mtd = try! minutes(amount=0)
  try
    @continuity_forge.BusinessImpactAssessment::new(
      service_id~,
      impact_score=60,
      rto=try! minutes(amount=0),
      rpo=try! minutes(amount=0),
      max_tolerable_downtime=zero_mtd,
    )
  catch {
    @continuity_forge.ModelError::InvalidDuration(message) =>
      inspect(message, content="max_tolerable_downtime must be positive")
    _ => fail("wrong error for zero maximum downtime")
  } noraise {
    _ => fail("expected a positive maximum downtime error")
  }
}
