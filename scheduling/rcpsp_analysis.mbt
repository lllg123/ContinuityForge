///|
/// Independent interpretation of a MoonBit heuristic result. This analysis
/// verifies feasibility but does not turn a heuristic into an optimal proof.
pub(all) struct RcpspAnalysis {
  status : String
  verified : Bool
  makespan : Int?
  lower_bound : Int
  gap_to_bound_percent : Double?
  mean_resource_utilization : Double?
  bottleneck_resource : String?
}

///|
pub fn analyze_rcpsp_result(
  problem : RcpspProblem,
  result : RcpspSolveResult,
) -> RcpspAnalysis raise SchedulingError {
  let lower_bound = rcpsp_lower_bound(problem)
  match result.status {
    "UNKNOWN" => {
      if !result.schedule.is_empty() || result.makespan is Some(_) {
        raise SchedulingError::InvalidSchedule(
          "UNKNOWN result carries a schedule",
        )
      }
      {
        status: "UNKNOWN",
        verified: false,
        makespan: None,
        lower_bound,
        gap_to_bound_percent: None,
        mean_resource_utilization: None,
        bottleneck_resource: None,
      }
    }
    "FEASIBLE" => {
      validate_rcpsp_schedule(problem, result.schedule)
      let makespan = rcpsp_makespan(result.schedule)
      if result.makespan != Some(makespan) || result.lower_bound != lower_bound {
        raise SchedulingError::InvalidSchedule(
          "inconsistent result bound or makespan",
        )
      }
      let mut total_work = 0.0
      let mut total_capacity = 0.0
      let mut bottleneck : String? = None
      let mut max_utilization = -1.0
      for resource in problem.resources {
        let mut work = 0.0
        for task in problem.tasks {
          for demand in task.demands {
            if demand.resource_id == resource.id {
              work = work +
                task.duration.to_double() * demand.amount.to_double()
            }
          }
        }
        total_work = total_work + work
        total_capacity = total_capacity + resource.capacity.to_double()
        if makespan > 0 {
          let utilization = work /
            (resource.capacity.to_double() * makespan.to_double())
          if utilization > max_utilization {
            max_utilization = utilization
            bottleneck = Some(resource.id)
          }
        }
      }
      let mean_resource_utilization = if total_capacity > 0.0 && makespan > 0 {
        Some(total_work / (total_capacity * makespan.to_double()))
      } else {
        None
      }
      let gap_to_bound_percent = if lower_bound > 0 {
        Some(
          100.0 * (makespan - lower_bound).to_double() / lower_bound.to_double(),
        )
      } else {
        None
      }
      {
        status: "FEASIBLE",
        verified: true,
        makespan: Some(makespan),
        lower_bound,
        gap_to_bound_percent,
        mean_resource_utilization,
        bottleneck_resource: bottleneck,
      }
    }
    _ =>
      raise SchedulingError::InvalidSchedule(
        "unsupported heuristic result status",
      )
  }
}
