///|
/// One build or test stage assigned to a named unit-capacity runner.
pub(all) struct PipelineStage {
  id : String
  duration : Int
  runner : String
  priority : Int
  prerequisites : Array[String]
}

///|
/// Comparable baseline and optimized results from the same generic problem.
pub(all) struct PipelineAnalysis {
  problem : @scheduling.SchedulingProblem
  baselines : Array[@scheduling.AnalysisResult]
  optimization : @scheduling.OptimizationReport
  bottleneck_runner : String?
  bottleneck_load : Int
  target_met : Bool?
}

///|
/// Maps pipeline stages to the same scheduler used for incident recovery.
/// Durations and the optional target use one caller-defined time unit.
pub fn analyze_pipeline(
  stages~ : Array[PipelineStage],
  runners~ : Array[String],
  target_makespan~ : Int?,
  search_budget~ : Int,
) -> PipelineAnalysis raise @scheduling.SchedulingError {
  let tasks : Array[@scheduling.Task] = []
  let dependencies : Array[@scheduling.Dependency] = []
  for stage in stages {
    tasks.push(
      @scheduling.Task::new(
        id=stage.id,
        duration=stage.duration,
        priority=stage.priority,
        resource_id=stage.runner,
      ),
    )
    for prerequisite in stage.prerequisites {
      dependencies.push(
        @scheduling.Dependency::new(
          task_id=stage.id,
          prerequisite_id=prerequisite,
        ),
      )
    }
  }
  let resources : Array[@scheduling.Resource] = []
  for runner in runners {
    resources.push(@scheduling.Resource::new(id=runner))
  }
  let checked = @scheduling.Constraints::new(resources~, target_makespan~)
  let problem = @scheduling.SchedulingProblem::new(tasks~, dependencies~, constraints={
    resources: checked.resources,
    target_makespan: None,
  })
  let baselines : Array[@scheduling.AnalysisResult] = []
  for
    baseline in [
      @scheduling.Baseline::StableTopological,
      @scheduling.Baseline::RecoveryHeuristic,
      @scheduling.Baseline::CriticalPath,
    ] {
    baselines.push(@scheduling.run_baseline(problem, baseline))
  }
  let optimization = @scheduling.optimize_schedule(problem, search_budget)
  let mut bottleneck_runner : String? = None
  let mut bottleneck_load = 0
  for runner in runners {
    let mut load = 0
    for stage in stages {
      if stage.runner == runner {
        load = load + stage.duration
      }
    }
    if load > bottleneck_load {
      bottleneck_load = load
      bottleneck_runner = Some(runner)
    }
  }
  let target_met = match target_makespan {
    Some(target) => Some(optimization.result.makespan <= target)
    None => None
  }
  {
    problem,
    baselines,
    optimization,
    bottleneck_runner,
    bottleneck_load,
    target_met,
  }
}
