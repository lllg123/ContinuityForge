///|
/// Synthetic pipeline: all durations are minutes; each runner has one slot.
fn stage(
  id : String,
  duration : Int,
  runner : String,
  priority : Int,
  prerequisites : Array[String],
) -> @pipeline.PipelineStage {
  { id, duration, runner, priority, prerequisites, }
}

///|
fn prerequisites_text(prerequisites : Array[String]) -> String {
  if prerequisites.is_empty() {
    return "-"
  }
  let mut result = ""
  for index, prerequisite in prerequisites {
    if index > 0 {
      result = result + ","
    }
    result = result + prerequisite
  }
  result
}

///|
fn main raise {
  let stages = [
    stage("lint", 5, "linux-a", 1, []),
    stage("compile-api", 12, "linux-a", 3, []),
    stage("compile-web", 9, "linux-b", 2, []),
    stage("unit-api", 8, "linux-a", 2, ["compile-api"]),
    stage("unit-web", 7, "linux-b", 2, ["compile-web"]),
    stage("integration", 11, "linux-c", 3, ["unit-api", "unit-web"]),
    stage("package", 4, "linux-a", 1, ["integration", "lint"]),
  ]
  let analysis = @pipeline.analyze_pipeline(
    stages~,
    runners=["linux-a", "linux-b", "linux-c"],
    target_makespan=Some(40),
    search_budget=100,
  )
  println("Synthetic CI pipeline; duration unit: minutes; runner capacity: 1")
  println("stage | runner | duration | prerequisites")
  for stage in stages {
    println(
      "\{stage.id} | \{stage.runner} | \{stage.duration} | \{prerequisites_text(stage.prerequisites)}",
    )
  }
  println("algorithm | makespan")
  for baseline in analysis.baselines {
    println("\{baseline.explanation.algorithm} | \{baseline.makespan}")
  }
  println("budgeted-search | \{analysis.optimization.result.makespan}")
  println("optimized stage | runner | start | finish")
  for entry in analysis.optimization.result.schedule {
    println(
      "\{entry.task_id} | \{entry.resource_id} | \{entry.start} | \{entry.finish}",
    )
  }
  match analysis.bottleneck_runner {
    Some(runner) =>
      println(
        "highest runner load: \{runner} = \{analysis.bottleneck_load} minutes",
      )
    None => println("highest runner load: none")
  }
  println("lower bound: \{analysis.optimization.lower_bound} minutes")
  match analysis.target_met {
    Some(true) => println("target <= 40 minutes: met")
    Some(false) => println("target <= 40 minutes: missed")
    None => println("target <= 40 minutes: not set")
  }
}
