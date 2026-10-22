///|
struct Case {
  name : String
  scale : String
  tasks : Int
  resources : Int
  dependency_pct : Int
  hot_share_pct : Int
  wide_duration : Bool
}

///|
struct Generator {
  mut state : Int
}

///|
fn Generator::next(self : Generator, limit : Int) -> Int {
  self.state = (self.state * 73 + 41) % 1000003
  self.state % limit
}

///|
struct Row {
  case_name : String
  scale : String
  seed : Int
  repeat : Int
  tasks : Int
  edges : Int
  resources : Int
  dependency_pct : Int
  duration_profile : String
  hot_share_pct : Int
  algorithm : String
  makespan : Int
  elapsed_ms : UInt64
  feasible : Bool
  gap_pct : Double?
  improvement_pct : Double
}

///|
fn cases() -> Array[Case] {
  [
    {
      name: "micro",
      scale: "Reference",
      tasks: 6,
      resources: 3,
      dependency_pct: 20,
      hot_share_pct: 50,
      wide_duration: false,
    },
    {
      name: "small-12",
      scale: "Small",
      tasks: 12,
      resources: 3,
      dependency_pct: 15,
      hot_share_pct: 70,
      wide_duration: false,
    },
    {
      name: "small-20",
      scale: "Small",
      tasks: 20,
      resources: 5,
      dependency_pct: 8,
      hot_share_pct: 0,
      wide_duration: true,
    },
    {
      name: "medium-50",
      scale: "Medium",
      tasks: 50,
      resources: 5,
      dependency_pct: 4,
      hot_share_pct: 60,
      wide_duration: false,
    },
    {
      name: "medium-100",
      scale: "Medium",
      tasks: 100,
      resources: 8,
      dependency_pct: 2,
      hot_share_pct: 0,
      wide_duration: true,
    },
    {
      name: "large-200",
      scale: "Large",
      tasks: 200,
      resources: 10,
      dependency_pct: 1,
      hot_share_pct: 70,
      wide_duration: true,
    },
  ]
}

///|
fn make_problem(
  config : Case,
  seed : Int,
) -> @scheduling.SchedulingProblem raise {
  let generator : Generator = { state: seed, }
  let resources : Array[@scheduling.Resource] = []
  for index in 0..<config.resources {
    resources.push(@scheduling.Resource::new(id="runner-\{index}"))
  }
  let tasks : Array[@scheduling.Task] = []
  for index in 0..<config.tasks {
    let runner = if generator.next(100) < config.hot_share_pct {
      0
    } else {
      generator.next(config.resources)
    }
    let duration = if config.wide_duration {
      1 + generator.next(30)
    } else {
      5 + generator.next(6)
    }
    tasks.push(
      @scheduling.Task::new(
        id="task-\{index}",
        duration~,
        priority=generator.next(4),
        resource_id="runner-\{runner}",
      ),
    )
  }
  let dependencies : Array[@scheduling.Dependency] = []
  for dependent in 1..<config.tasks {
    for prerequisite in 0..<dependent {
      if generator.next(100) < config.dependency_pct {
        dependencies.push(
          @scheduling.Dependency::new(
            task_id="task-\{dependent}",
            prerequisite_id="task-\{prerequisite}",
          ),
        )
      }
    }
  }
  @scheduling.SchedulingProblem::new(
    tasks~,
    dependencies~,
    constraints=@scheduling.Constraints::new(resources~, target_makespan=None),
  )
}

///|
fn duration_name(config : Case) -> String {
  if config.wide_duration {
    "wide-1-30"
  } else {
    "narrow-5-10"
  }
}

///|
fn percent(numerator : Int, denominator : Int) -> Double {
  if denominator == 0 {
    0.0
  } else {
    numerator.to_double() * 100.0 / denominator.to_double()
  }
}

///|
fn measure(
  problem : @scheduling.SchedulingProblem,
  config : Case,
  seed : Int,
  repeat : Int,
  algorithm : String,
  reference : @scheduling.ExactReference?,
  stable_makespan : Int,
) -> Row raise {
  let started = @env.now()
  let result = match algorithm {
    "stable-topological" =>
      @scheduling.run_baseline(problem, @scheduling.Baseline::StableTopological)
    "recovery-heuristic" =>
      @scheduling.run_baseline(problem, @scheduling.Baseline::RecoveryHeuristic)
    "critical-path" =>
      @scheduling.run_baseline(problem, @scheduling.Baseline::CriticalPath)
    _ => @scheduling.optimize_schedule(problem, 10).result
  }
  let elapsed_ms = @env.now() - started
  let feasible = try {
    @scheduling.validate_schedule(problem, result.schedule)
    true
  } catch {
    _ => false
  }
  let gap_pct = match reference {
    Some(exact) =>
      if exact.proven_optimal {
        Some(@scheduling.optimality_gap_percent(result, exact))
      } else {
        None
      }
    None => None
  }
  {
    case_name: config.name,
    scale: config.scale,
    seed,
    repeat,
    tasks: config.tasks,
    edges: problem.dependencies.length(),
    resources: config.resources,
    dependency_pct: config.dependency_pct,
    duration_profile: duration_name(config),
    hot_share_pct: config.hot_share_pct,
    algorithm,
    makespan: result.makespan,
    elapsed_ms,
    feasible,
    gap_pct,
    improvement_pct: percent(stable_makespan - result.makespan, stable_makespan),
  }
}

///|
fn run_cases() -> Array[Row] raise {
  let rows : Array[Row] = []
  for config in cases() {
    for repeat in 0..<3 {
      let seed = 20261021 + repeat * 1009
      let problem = make_problem(config, seed)
      let reference = if config.tasks <= 8 {
        Some(@scheduling.exact_reference(problem, 100000))
      } else {
        None
      }
      let stable = @scheduling.run_baseline(
        problem,
        @scheduling.Baseline::StableTopological,
      )
      for
        algorithm in [
          "stable-topological", "recovery-heuristic", "critical-path", "budgeted-search",
        ] {
        rows.push(
          measure(
            problem,
            config,
            seed,
            repeat + 1,
            algorithm,
            reference,
            stable.makespan,
          ),
        )
      }
    }
  }
  rows
}

///|
struct AblationRow {
  case_name : String
  seed : Int
  variant : String
  makespan : Int
  full_makespan : Int
  feasible : Bool
}

///|
fn run_ablation() -> Array[AblationRow] raise {
  let rows : Array[AblationRow] = []
  for config in cases() {
    for repeat in 0..<3 {
      let seed = 20261021 + repeat * 1009
      let problem = make_problem(config, seed)
      let full = @scheduling.optimize_schedule(problem, 10).result.makespan
      for
        variant in [
          "full", "no-critical-path", "no-resource-load", "no-local-search",
        ] {
        let critical = variant != "no-critical-path"
        let load = variant != "no-resource-load"
        let search = variant != "no-local-search"
        let result = @scheduling.optimize_schedule_with_features(
            problem, 10, critical, load, search,
          ).result
        let feasible = try {
          @scheduling.validate_schedule(problem, result.schedule)
          true
        } catch {
          _ => false
        }
        rows.push({
          case_name: config.name,
          seed,
          variant,
          makespan: result.makespan,
          full_makespan: full,
          feasible,
        })
      }
    }
  }
  let trap = local_order_trap()
  let trap_full = @scheduling.optimize_schedule(trap, 10).result.makespan
  for
    variant in [
      "full", "no-critical-path", "no-resource-load", "no-local-search",
    ] {
    let result = @scheduling.optimize_schedule_with_features(
        trap,
        10,
        variant != "no-critical-path",
        variant != "no-resource-load",
        variant != "no-local-search",
      ).result
    let feasible = try {
      @scheduling.validate_schedule(trap, result.schedule)
      true
    } catch {
      _ => false
    }
    rows.push({
      case_name: "local-order-trap",
      seed: 0,
      variant,
      makespan: result.makespan,
      full_makespan: trap_full,
      feasible,
    })
  }
  rows
}

///|
fn local_order_trap() -> @scheduling.SchedulingProblem raise {
  @scheduling.SchedulingProblem::new(
    tasks=[
      @scheduling.Task::new(
        id="a",
        duration=10,
        priority=3,
        resource_id="shared",
      ),
      @scheduling.Task::new(
        id="b",
        duration=1,
        priority=0,
        resource_id="shared",
      ),
      @scheduling.Task::new(
        id="c",
        duration=1,
        priority=3,
        resource_id="runner-c",
      ),
      @scheduling.Task::new(
        id="d",
        duration=8,
        priority=0,
        resource_id="runner-d",
      ),
    ],
    dependencies=[
      @scheduling.Dependency::new(task_id="c", prerequisite_id="a"),
      @scheduling.Dependency::new(task_id="d", prerequisite_id="b"),
    ],
    constraints=@scheduling.Constraints::new(
      resources=[
        @scheduling.Resource::new(id="shared"),
        @scheduling.Resource::new(id="runner-c"),
        @scheduling.Resource::new(id="runner-d"),
      ],
      target_makespan=None,
    ),
  )
}

///|
fn ablation_csv(rows : Array[AblationRow]) -> Unit {
  println("case,seed,variant,makespan,full_makespan,delta_from_full,feasible")
  for row in rows {
    println(
      "\{row.case_name},\{row.seed},\{row.variant},\{row.makespan},\{row.full_makespan},\{row.makespan - row.full_makespan},\{row.feasible}",
    )
  }
}

///|
fn ablation_summary(rows : Array[AblationRow]) -> Unit {
  println(
    "case,variant,observations,feasible_count,mean_makespan,mean_delta_from_full",
  )
  for
    case_name in [
      "micro", "small-12", "small-20", "medium-50", "medium-100", "large-200", "local-order-trap",
    ] {
    for
      variant in [
        "full", "no-critical-path", "no-resource-load", "no-local-search",
      ] {
      let mut count = 0
      let mut feasible = 0
      let mut makespan_sum = 0
      let mut delta_sum = 0
      for row in rows {
        if row.case_name == case_name && row.variant == variant {
          count = count + 1
          if row.feasible {
            feasible = feasible + 1
          }
          makespan_sum = makespan_sum + row.makespan
          delta_sum = delta_sum + row.makespan - row.full_makespan
        }
      }
      println(
        "\{case_name},\{variant},\{count},\{feasible},\{makespan_sum.to_double() / count.to_double()},\{delta_sum.to_double() / count.to_double()}",
      )
    }
  }
}

///|
fn gap_text(gap : Double?) -> String {
  match gap {
    Some(value) => "\{value}"
    None => ""
  }
}

///|
fn csv(rows : Array[Row]) -> Unit {
  println(
    "case,scale,seed,repeat,tasks,edges,resources,dependency_pct,duration_profile,hot_share_pct,algorithm,makespan,elapsed_ms,feasible,optimality_gap_pct,improvement_pct",
  )
  for row in rows {
    let feasible = if row.feasible { "true" } else { "false" }
    println(
      "\{row.case_name},\{row.scale},\{row.seed},\{row.repeat},\{row.tasks},\{row.edges},\{row.resources},\{row.dependency_pct},\{row.duration_profile},\{row.hot_share_pct},\{row.algorithm},\{row.makespan},\{row.elapsed_ms},\{feasible},\{gap_text(row.gap_pct)},\{row.improvement_pct}",
    )
  }
}

///|
fn json_gap(gap : Double?) -> String {
  match gap {
    Some(value) => "\{value}"
    None => "null"
  }
}

///|
fn json(rows : Array[Row]) -> Unit {
  println(
    "{\"schema_version\":1,\"data\":\"synthetic\",\"base_seed\":20261021,\"repeats\":3,\"search_budget\":10,\"rows\":[",
  )
  for index, row in rows {
    let feasible = if row.feasible { "true" } else { "false" }
    let separator = if index + 1 == rows.length() { "" } else { "," }
    println(
      "{\"case\":\"\{row.case_name}\",\"scale\":\"\{row.scale}\",\"seed\":\{row.seed},\"repeat\":\{row.repeat},\"tasks\":\{row.tasks},\"edges\":\{row.edges},\"resources\":\{row.resources},\"dependency_pct\":\{row.dependency_pct},\"duration_profile\":\"\{row.duration_profile}\",\"hot_share_pct\":\{row.hot_share_pct},\"algorithm\":\"\{row.algorithm}\",\"makespan\":\{row.makespan},\"elapsed_ms\":\{row.elapsed_ms},\"feasible\":\{feasible},\"optimality_gap_pct\":\{json_gap(row.gap_pct)},\"improvement_pct\":\{row.improvement_pct}}\{separator}",
    )
  }
  println("]}")
}

///|
fn svg(rows : Array[Row], runtime : Bool) -> Unit {
  let algorithms = [
    "stable-topological", "recovery-heuristic", "critical-path", "budgeted-search",
  ]
  let colors = ["#4e79a7", "#f28e2b", "#59a14f", "#e15759"]
  let mut maximum = 0
  for row in rows {
    let value = if runtime { row.elapsed_ms.to_int() } else { row.makespan }
    if value > maximum {
      maximum = value
    }
  }
  println(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1050\" height=\"570\" viewBox=\"0 0 1050 570\">",
  )
  println("<rect width=\"1050\" height=\"570\" fill=\"white\"/>")
  let title = if runtime {
    "mean execution time (ms)"
  } else {
    "mean makespan (time units)"
  }
  println(
    "<text x=\"35\" y=\"35\" font-family=\"sans-serif\" font-size=\"23\">Synthetic scheduling benchmark: \{title}</text>",
  )
  println(
    "<text x=\"35\" y=\"58\" font-family=\"sans-serif\" font-size=\"13\">Three fixed-seed repeats per case; smaller is better. Reference has six tasks.</text>",
  )
  for case_index, config in cases() {
    let base_x = 50 + case_index * 165
    for algorithm_index, algorithm in algorithms {
      let mut sum = 0
      let mut count = 0
      for row in rows {
        if row.case_name == config.name && row.algorithm == algorithm {
          sum = sum +
            (if runtime { row.elapsed_ms.to_int() } else { row.makespan })
          count = count + 1
        }
      }
      let mean = sum / count
      let height = if maximum == 0 { 0 } else { mean * 380 / maximum }
      let x = base_x + algorithm_index * 30
      let y = 460 - height
      println(
        "<rect x=\"\{x}\" y=\"\{y}\" width=\"25\" height=\"\{height}\" fill=\"\{colors[algorithm_index]}\"/>",
      )
    }
    println(
      "<text x=\"\{base_x}\" y=\"480\" font-family=\"sans-serif\" font-size=\"13\">\{config.name}</text>",
    )
  }
  for index, algorithm in algorithms {
    let x = 35 + index * 250
    println(
      "<rect x=\"\{x}\" y=\"515\" width=\"15\" height=\"15\" fill=\"\{colors[index]}\"/>",
    )
    println(
      "<text x=\"\{x + 22}\" y=\"528\" font-family=\"sans-serif\" font-size=\"13\">\{algorithm}</text>",
    )
  }
  println("</svg>")
}

///|
fn summary(rows : Array[Row]) -> Unit {
  println(
    "case,scale,tasks,algorithm,observations,feasibility_rate_pct,mean_makespan,mean_elapsed_ms,mean_improvement_pct,proven_reference_count",
  )
  for config in cases() {
    for
      algorithm in [
        "stable-topological", "recovery-heuristic", "critical-path", "budgeted-search",
      ] {
      let mut count = 0
      let mut feasible = 0
      let mut makespan_sum = 0
      let mut elapsed_sum : UInt64 = 0
      let mut improvement_sum = 0.0
      let mut references = 0
      for row in rows {
        if row.case_name == config.name && row.algorithm == algorithm {
          count = count + 1
          if row.feasible {
            feasible = feasible + 1
          }
          makespan_sum = makespan_sum + row.makespan
          elapsed_sum = elapsed_sum + row.elapsed_ms
          improvement_sum = improvement_sum + row.improvement_pct
          match row.gap_pct {
            Some(_) => references = references + 1
            None => ()
          }
        }
      }
      println(
        "\{config.name},\{config.scale},\{config.tasks},\{algorithm},\{count},\{percent(feasible, count)},\{makespan_sum.to_double() / count.to_double()},\{elapsed_sum.to_double() / count.to_double()},\{improvement_sum / count.to_double()},\{references}",
      )
    }
  }
}

///|
fn main raise {
  let args = @env.args()
  let mode = if args.length() <= 2 { "csv" } else { args[args.length() - 1] }
  if mode == "ablation-csv" || mode == "ablation-summary" {
    let rows = run_ablation()
    if mode == "ablation-csv" {
      ablation_csv(rows)
    } else {
      ablation_summary(rows)
    }
    return
  }
  if mode != "csv" &&
    mode != "json" &&
    mode != "svg" &&
    mode != "time-svg" &&
    mode != "summary" {
    abort("expected csv, json, svg, time-svg, or summary")
  }
  let rows = run_cases()
  match mode {
    "csv" => csv(rows)
    "json" => json(rows)
    "svg" => svg(rows, false)
    "time-svg" => svg(rows, true)
    _ => summary(rows)
  }
}
