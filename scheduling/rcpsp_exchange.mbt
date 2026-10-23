///|
struct RcpspJsonResource {
  id : String
  capacity : Int
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonResource with @json.FromJson::{from_json}

///|
pub extend RcpspJsonResource with ToJson::{to_json}

///|
struct RcpspJsonDemand {
  resource_id : String
  amount : Int
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonDemand with @json.FromJson::{from_json}

///|
pub extend RcpspJsonDemand with ToJson::{to_json}

///|
struct RcpspJsonTask {
  id : String
  duration : Int
  priority : Int
  demands : Array[RcpspJsonDemand]
  release_time : Int
  deadline : Int?
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonTask with @json.FromJson::{from_json}

///|
pub extend RcpspJsonTask with ToJson::{to_json}

///|
struct RcpspJsonDependency {
  task_id : String
  prerequisite_id : String
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonDependency with @json.FromJson::{from_json}

///|
pub extend RcpspJsonDependency with ToJson::{to_json}

///|
struct RcpspJsonOptions {
  algorithm : String
  search_budget : Int
  time_limit_ms : Int
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonOptions with @json.FromJson::{from_json}

///|
pub extend RcpspJsonOptions with ToJson::{to_json}

///|
struct RcpspJsonProblem {
  schema_version : String
  time_unit : String
  resources : Array[RcpspJsonResource]
  tasks : Array[RcpspJsonTask]
  dependencies : Array[RcpspJsonDependency]
  target_makespan : Int?
  solve_options : RcpspJsonOptions?
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonProblem with @json.FromJson::{from_json}

///|
pub extend RcpspJsonProblem with ToJson::{to_json}

///|
struct RcpspJsonEntry {
  task_id : String
  start : Int
  finish : Int
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonEntry with @json.FromJson::{from_json}

///|
pub extend RcpspJsonEntry with ToJson::{to_json}

///|
struct RcpspJsonSolution {
  schema_version : String
  status : String
  algorithm : String
  schedule : Array[RcpspJsonEntry]
  makespan : Int?
  lower_bound : Int?
  candidates_evaluated : Int
  accepted_moves : Int
  budget : Int
  elapsed_ms : Int
  diagnostic : String?
} derive(FromJson, ToJson)

///|
pub extend RcpspJsonSolution with @json.FromJson::{from_json}

///|
pub extend RcpspJsonSolution with ToJson::{to_json}

///|
/// The canonical v2 exchange keeps all problem constraints. Optional fields
/// are omitted when absent. Parsing is followed by the independent validator.
pub fn import_rcpsp_problem(input : String) -> RcpspProblem raise {
  let raw : RcpspJsonProblem = @json.from_json(@json.parse(input))
  if raw.schema_version != "continuityforge.rcpsp.v2" {
    raise SchedulingError::InvalidConstraint("unsupported RCPSP schema version")
  }
  if raw.time_unit == "" {
    raise SchedulingError::InvalidConstraint("time_unit cannot be empty")
  }
  match raw.solve_options {
    Some(value) => {
      let _ = RcpspSolveOptions::new(
        algorithm=value.algorithm,
        search_budget=value.search_budget,
        time_limit_ms=value.time_limit_ms,
      )
    }
    None => ()
  }
  let resources : Array[RenewableResource] = []
  for resource in raw.resources {
    resources.push(
      RenewableResource::new(id=resource.id, capacity=resource.capacity),
    )
  }
  let tasks : Array[RcpspTask] = []
  for task in raw.tasks {
    let demands : Array[ResourceDemand] = []
    for demand in task.demands {
      demands.push(
        ResourceDemand::new(
          resource_id=demand.resource_id,
          amount=demand.amount,
        ),
      )
    }
    tasks.push(
      RcpspTask::new(
        id=task.id,
        duration=task.duration,
        priority=task.priority,
        demands~,
        release_time=task.release_time,
        deadline=task.deadline,
      ),
    )
  }
  let dependencies : Array[Dependency] = []
  for edge in raw.dependencies {
    dependencies.push(
      Dependency::new(
        task_id=edge.task_id,
        prerequisite_id=edge.prerequisite_id,
      ),
    )
  }
  RcpspProblem::new(
    tasks~,
    dependencies~,
    resources~,
    target_makespan=raw.target_makespan,
  )
}

///|
pub fn export_rcpsp_problem(
  problem : RcpspProblem,
  time_unit : String,
) -> String raise SchedulingError {
  validate_rcpsp_problem(problem)
  if time_unit == "" {
    raise SchedulingError::InvalidConstraint("time_unit cannot be empty")
  }
  let resources : Array[RcpspJsonResource] = []
  for resource in problem.resources {
    resources.push({ id: resource.id, capacity: resource.capacity, })
  }
  let tasks : Array[RcpspJsonTask] = []
  for task in problem.tasks {
    let demands : Array[RcpspJsonDemand] = []
    for demand in task.demands {
      demands.push({ resource_id: demand.resource_id, amount: demand.amount, })
    }
    tasks.push({
      id: task.id,
      duration: task.duration,
      priority: task.priority,
      demands,
      release_time: task.release_time,
      deadline: task.deadline,
    })
  }
  let dependencies : Array[RcpspJsonDependency] = []
  for edge in problem.dependencies {
    dependencies.push({
      task_id: edge.task_id,
      prerequisite_id: edge.prerequisite_id,
    })
  }
  @json.to_json(RcpspJsonProblem::{
    schema_version: "continuityforge.rcpsp.v2",
    time_unit,
    resources,
    tasks,
    dependencies,
    target_makespan: problem.target_makespan,
    solve_options: None,
  }).stringify()
}

///|
/// Solver parameters are part of the request envelope, separate from the
/// physical scheduling constraints. CP-SAT's time limit is advisory to its
/// caller; the MoonBit heuristics use search_budget only.
pub(all) struct RcpspSolveOptions {
  algorithm : String
  search_budget : Int
  time_limit_ms : Int
}

///|
pub fn RcpspSolveOptions::new(
  algorithm~ : String,
  search_budget~ : Int,
  time_limit_ms~ : Int,
) -> RcpspSolveOptions raise SchedulingError {
  if algorithm != "stable-topological" &&
    algorithm != "critical-path" &&
    algorithm != "recovery-heuristic" &&
    algorithm != "budgeted-local-search" {
    raise SchedulingError::InvalidConstraint("unknown RCPSP algorithm")
  }
  if search_budget < 0 || time_limit_ms <= 0 {
    raise SchedulingError::InvalidConstraint("invalid RCPSP solver budget")
  }
  { algorithm, search_budget, time_limit_ms, }
}

///|
pub(all) struct RcpspRequest {
  problem : RcpspProblem
  time_unit : String
  solve_options : RcpspSolveOptions
}

///|
pub fn import_rcpsp_request(input : String) -> RcpspRequest raise {
  let raw : RcpspJsonProblem = @json.from_json(@json.parse(input))
  let problem = import_rcpsp_problem(input)
  let options = match raw.solve_options {
    Some(value) =>
      RcpspSolveOptions::new(
        algorithm=value.algorithm,
        search_budget=value.search_budget,
        time_limit_ms=value.time_limit_ms,
      )
    None =>
      RcpspSolveOptions::new(
        algorithm="budgeted-local-search",
        search_budget=30,
        time_limit_ms=5000,
      )
  }
  { problem, time_unit: raw.time_unit, solve_options: options, }
}

///|
pub fn export_rcpsp_request(request : RcpspRequest) -> String raise {
  let options = RcpspSolveOptions::new(
    algorithm=request.solve_options.algorithm,
    search_budget=request.solve_options.search_budget,
    time_limit_ms=request.solve_options.time_limit_ms,
  )
  let raw : RcpspJsonProblem = @json.from_json(
    @json.parse(export_rcpsp_problem(request.problem, request.time_unit)),
  )
  @json.to_json(RcpspJsonProblem::{
    schema_version: raw.schema_version,
    time_unit: raw.time_unit,
    resources: raw.resources,
    tasks: raw.tasks,
    dependencies: raw.dependencies,
    target_makespan: raw.target_makespan,
    solve_options: Some({
      algorithm: options.algorithm,
      search_budget: options.search_budget,
      time_limit_ms: options.time_limit_ms,
    }),
  }).stringify()
}

///|
pub fn solve_rcpsp_request(
  request : RcpspRequest,
) -> RcpspSolveResult raise SchedulingError {
  let options = RcpspSolveOptions::new(
    algorithm=request.solve_options.algorithm,
    search_budget=request.solve_options.search_budget,
    time_limit_ms=request.solve_options.time_limit_ms,
  )
  match options.algorithm {
    "stable-topological" => solve_rcpsp(request.problem, StableTopological)
    "critical-path" => solve_rcpsp(request.problem, CriticalPath)
    "recovery-heuristic" => solve_rcpsp(request.problem, RecoveryHeuristic)
    "budgeted-local-search" =>
      optimize_rcpsp(request.problem, options.search_budget)
    _ => abort("validated algorithm disappeared")
  }
}

///|
/// Imports any solver's result and validates its schedule under the supplied
/// problem. UNKNOWN carries no candidate; infeasible claims are not certified.
pub fn import_rcpsp_solution(
  problem : RcpspProblem,
  input : String,
) -> Array[RcpspScheduleEntry] raise {
  let raw : RcpspJsonSolution = @json.from_json(@json.parse(input))
  if raw.schema_version != "continuityforge.rcpsp.solution.v2" {
    raise SchedulingError::InvalidSchedule(
      "unsupported solution schema version",
    )
  }
  if raw.status != "FEASIBLE" && raw.status != "OPTIMAL" {
    raise SchedulingError::InvalidSchedule("solution has no feasible candidate")
  }
  let schedule : Array[RcpspScheduleEntry] = []
  for entry in raw.schedule {
    schedule.push(
      RcpspScheduleEntry::new(
        task_id=entry.task_id,
        start=entry.start,
        finish=entry.finish,
      ),
    )
  }
  validate_rcpsp_schedule(problem, schedule)
  if raw.makespan != Some(rcpsp_makespan(schedule)) {
    raise SchedulingError::InvalidSchedule(
      "reported makespan differs from schedule",
    )
  }
  schedule
}

///|
pub fn export_rcpsp_solution(result : RcpspSolveResult) -> String {
  let schedule : Array[RcpspJsonEntry] = []
  for entry in result.schedule {
    schedule.push({
      task_id: entry.task_id,
      start: entry.start,
      finish: entry.finish,
    })
  }
  @json.to_json(RcpspJsonSolution::{
    schema_version: "continuityforge.rcpsp.solution.v2",
    status: result.status,
    algorithm: result.algorithm,
    schedule,
    makespan: result.makespan,
    lower_bound: Some(result.lower_bound),
    candidates_evaluated: result.candidates_evaluated,
    accepted_moves: result.accepted_moves,
    budget: result.budget,
    elapsed_ms: result.elapsed_ms,
    diagnostic: result.diagnostic,
  }).stringify()
}
