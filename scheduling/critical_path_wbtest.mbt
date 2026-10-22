///|
test "critical path explains dependency lower bound without resource delay" {
  let tasks = [
    try! Task::new(id="db", duration=10, priority=0, resource_id="data"),
    try! Task::new(id="api", duration=20, priority=0, resource_id="platform"),
    try! Task::new(id="worker", duration=15, priority=0, resource_id="platform"),
    try! Task::new(id="side", duration=5, priority=0, resource_id="data"),
  ]
  let dependencies = [
    try! Dependency::new(task_id="api", prerequisite_id="db"),
    try! Dependency::new(task_id="worker", prerequisite_id="api"),
  ]
  let resources = [
    try! Resource::new(id="data"),
    try! Resource::new(id="platform"),
  ]
  let problem = try! SchedulingProblem::new(
    tasks~,
    dependencies~,
    constraints=try! Constraints::new(resources~, target_makespan=None),
  )
  let path = try! critical_path(problem)
  assert_eq(path.task_ids, ["db", "api", "worker"])
  assert_eq(path.duration, 45)
}
