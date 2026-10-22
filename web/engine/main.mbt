///|
struct WebAsset {
  id : String
  asset_type : String
  depends_on : Array[String]
  duration : Int
  resource : String
  priority : Int
} derive(FromJson)

///|
struct WebRequest {
  assets : Array[WebAsset]
  failed_asset_id : String
  target_window : Int
  search_budget : Int
} derive(FromJson)

///|
struct WebImpact {
  asset_id : String
  path : Array[String]
} derive(FromJson, ToJson)

///|
struct WebScheduleEntry {
  asset_id : String
  resource : String
  start : Int
  finish : Int
} derive(FromJson, ToJson)

///|
struct WebAlgorithm {
  name : String
  makespan : Int
  schedule : Array[WebScheduleEntry]
} derive(FromJson, ToJson)

///|
struct WebResult {
  dependency_order : Array[String]
  affected : Array[WebImpact]
  baselines : Array[WebAlgorithm]
  optimized : WebAlgorithm
  lower_bound : Int
  target_met : Bool
  bottleneck_resource : String?
  bottleneck_load : Int
} derive(FromJson, ToJson)

///|
struct EngineReply {
  ok : Bool
  result : WebResult?
  error : String?
} derive(FromJson, ToJson)

///|
suberror WebError {
  InvalidInput(String)
}

///|
fn asset_ref(asset : WebAsset) -> @continuity_forge.AssetRef raise {
  match asset.asset_type {
    "Service" =>
      @continuity_forge.AssetRef::Service(
        @continuity_forge.ServiceId::new(value=asset.id),
      )
    "Component" =>
      @continuity_forge.AssetRef::Component(
        @continuity_forge.ComponentId::new(value=asset.id),
      )
    _ => raise WebError::InvalidInput("unknown asset_type: \{asset.asset_type}")
  }
}

///|
fn ref_id(asset : @continuity_forge.AssetRef) -> String {
  match asset {
    @continuity_forge.AssetRef::Service(id) => id.value
    @continuity_forge.AssetRef::Component(id) => id.value
  }
}

///|
fn web_algorithm(
  result : @scheduling.AnalysisResult,
  name : String,
) -> WebAlgorithm {
  let schedule : Array[WebScheduleEntry] = []
  for entry in result.schedule {
    schedule.push({
      asset_id: entry.task_id,
      resource: entry.resource_id,
      start: entry.start,
      finish: entry.finish,
    })
  }
  { name, makespan: result.makespan, schedule, }
}

///|
fn compute(request : WebRequest) -> WebResult raise {
  if request.target_window < 0 || request.search_budget < 0 {
    raise WebError::InvalidInput(
      "target_window and search_budget must be nonnegative",
    )
  }
  let refs : Array[@continuity_forge.AssetRef] = []
  let domain_edges : Array[@continuity_forge.Dependency] = []
  let tasks : Array[@scheduling.Task] = []
  let edges : Array[@scheduling.Dependency] = []
  let resources : Array[@scheduling.Resource] = []
  for asset in request.assets {
    refs.push(asset_ref(asset))
    tasks.push(
      @scheduling.Task::new(
        id=asset.id,
        duration=asset.duration,
        priority=asset.priority,
        resource_id=asset.resource,
      ),
    )
    let mut exists = false
    for resource in resources {
      if resource.id == asset.resource {
        exists = true
      }
    }
    if !exists {
      resources.push(@scheduling.Resource::new(id=asset.resource))
    }
  }
  for asset in request.assets {
    for prerequisite in asset.depends_on {
      let mut dependency_ref : @continuity_forge.AssetRef? = None
      for candidate in request.assets {
        if candidate.id == prerequisite {
          dependency_ref = Some(asset_ref(candidate))
        }
      }
      let dependency_ref = match dependency_ref {
        Some(value) => value
        None =>
          raise WebError::InvalidInput("unknown dependency: \{prerequisite}")
      }
      domain_edges.push(
        @continuity_forge.define_dependency(
          dependent=asset_ref(asset),
          dependency=dependency_ref,
        ),
      )
      edges.push(
        @scheduling.Dependency::new(
          task_id=asset.id,
          prerequisite_id=prerequisite,
        ),
      )
    }
  }
  let dependency_order : Array[String] = []
  for
    item in @continuity_forge.order_dependencies(
      assets=refs,
      dependencies=domain_edges,
    ) {
    dependency_order.push(ref_id(item))
  }
  let affected : Array[WebImpact] = []
  if request.failed_asset_id != "" {
    let mut failed : @continuity_forge.AssetRef? = None
    for asset in request.assets {
      if asset.id == request.failed_asset_id {
        failed = Some(asset_ref(asset))
      }
    }
    let failed = match failed {
      Some(value) => value
      None =>
        raise WebError::InvalidInput(
          "unknown failed_asset_id: \{request.failed_asset_id}",
        )
    }
    let impact = @continuity_forge.simulate_impact(
      failed_asset=failed,
      assets=refs,
      dependencies=domain_edges,
    )
    for item in impact.paths {
      let path : Array[String] = []
      for node in item.path {
        path.push(ref_id(node))
      }
      affected.push({ asset_id: ref_id(item.affected_asset), path, })
    }
  }
  let problem = @scheduling.SchedulingProblem::new(
    tasks~,
    dependencies=edges,
    constraints=@scheduling.Constraints::new(resources~, target_makespan=None),
  )
  let baselines : Array[WebAlgorithm] = []
  for
    baseline in [
      @scheduling.Baseline::StableTopological,
      @scheduling.Baseline::RecoveryHeuristic,
      @scheduling.Baseline::CriticalPath,
    ] {
    let result = @scheduling.run_baseline(problem, baseline)
    baselines.push(web_algorithm(result, result.explanation.algorithm))
  }
  let optimization = @scheduling.optimize_schedule(
    problem,
    request.search_budget,
  )
  let mut bottleneck_resource : String? = None
  let mut bottleneck_load = 0
  for resource in resources {
    let mut load = 0
    for task in tasks {
      if task.resource_id == resource.id {
        load = load + task.duration
      }
    }
    if load > bottleneck_load {
      bottleneck_resource = Some(resource.id)
      bottleneck_load = load
    }
  }
  {
    dependency_order,
    affected,
    baselines,
    optimized: web_algorithm(optimization.result, "budgeted-search"),
    lower_bound: optimization.lower_bound,
    target_met: optimization.result.makespan <= request.target_window,
    bottleneck_resource,
    bottleneck_load,
  }
}

///|
/// Browser-facing JSON boundary. Domain and scheduling errors stay structured.
pub fn analyze_workspace(input : String) -> String {
  let reply = try {
    let request : WebRequest = @json.from_json(@json.parse(input))
    let result = compute(request)
    EngineReply::{ ok: true, result: Some(result), error: None, }
  } catch {
    WebError::InvalidInput(message) =>
      EngineReply::{ ok: false, result: None, error: Some(message), }
    @continuity_forge.ModelError::EmptyField(message) =>
      EngineReply::{
        ok: false,
        result: None,
        error: Some("empty field: \{message}"),
      }
    @continuity_forge.ModelError::SelfDependency(message) =>
      EngineReply::{
        ok: false,
        result: None,
        error: Some("self dependency: \{message}"),
      }
    @continuity_forge.ModelError::DuplicateAsset(message) =>
      EngineReply::{
        ok: false,
        result: None,
        error: Some("duplicate asset: \{message}"),
      }
    @continuity_forge.ModelError::MissingAsset(message) =>
      EngineReply::{
        ok: false,
        result: None,
        error: Some("missing asset: \{message}"),
      }
    @continuity_forge.ModelError::DuplicateDependency(message) =>
      EngineReply::{
        ok: false,
        result: None,
        error: Some("duplicate dependency: \{message}"),
      }
    @continuity_forge.ModelError::DependencyCycle(message) =>
      EngineReply::{
        ok: false,
        result: None,
        error: Some("dependency cycle: \{message}"),
      }
    @scheduling.SchedulingError::InvalidTask(message)
    | @scheduling.SchedulingError::InvalidResource(message)
    | @scheduling.SchedulingError::InvalidDependency(message)
    | @scheduling.SchedulingError::InvalidConstraint(message)
    | @scheduling.SchedulingError::InvalidSchedule(message) =>
      EngineReply::{ ok: false, result: None, error: Some(message), }
    error =>
      EngineReply::{ ok: false, result: None, error: Some(error.to_string()), }
  }
  @json.to_json(reply).stringify()
}

///|
fn main {

}
