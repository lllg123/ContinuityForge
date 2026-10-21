///|
test "fixed seed reproduces the same synthetic scheduling instance" {
  let config = cases()[2]
  let first = try! make_problem(config, 20261021)
  let second = try! make_problem(config, 20261021)
  assert_eq(first.tasks.length(), 20)
  assert_eq(first.dependencies.length(), second.dependencies.length())
  for index, task in first.tasks {
    let other = second.tasks[index]
    assert_eq(task.id, other.id)
    assert_eq(task.duration, other.duration)
    assert_eq(task.resource_id, other.resource_id)
    assert_eq(task.priority, other.priority)
  }
  for index, edge in first.dependencies {
    let other = second.dependencies[index]
    assert_eq(edge.task_id, other.task_id)
    assert_eq(edge.prerequisite_id, other.prerequisite_id)
  }
  try! @scheduling.validate_problem(first)
}

///|
test "benchmark covers all cases and only reports proven exact gaps" {
  let rows = try! run_cases()
  assert_eq(rows.length(), 72)
  let mut reference_count = 0
  for row in rows {
    assert_true(row.feasible)
    assert_true(row.makespan > 0)
    match row.gap_pct {
      Some(gap) => {
        assert_eq(row.case_name, "micro")
        assert_true(gap >= 0.0)
        reference_count = reference_count + 1
      }
      None => assert_true(row.case_name != "micro")
    }
  }
  assert_eq(reference_count, 12)
}
