///|
/// Exported JavaScript boundary for canonical v2 problem files.
pub fn solve_json(input : String, algorithm : String, budget : Int) -> String {
  try {
    let problem = @scheduling.import_rcpsp_problem(input)
    let result = match algorithm {
      "stable-topological" =>
        @scheduling.solve_rcpsp(
          problem,
          @scheduling.RcpspAlgorithm::StableTopological,
        )
      "critical-path" =>
        @scheduling.solve_rcpsp(
          problem,
          @scheduling.RcpspAlgorithm::CriticalPath,
        )
      "recovery-heuristic" =>
        @scheduling.solve_rcpsp(
          problem,
          @scheduling.RcpspAlgorithm::RecoveryHeuristic,
        )
      "budgeted-local-search" => @scheduling.optimize_rcpsp(problem, budget)
      _ =>
        raise @scheduling.SchedulingError::InvalidConstraint(
          "unknown RCPSP algorithm",
        )
    }
    @scheduling.export_rcpsp_solution(result)
  } catch {
    error => {
      let message = @json.to_json(error.to_string()).stringify()
      "{\"error\":\{message}}"
    }
  }
}

///|
/// External candidate validation uses the same MoonBit constraint checker.
pub fn validate_json(problem_input : String, solution_input : String) -> String {
  try {
    let problem = @scheduling.import_rcpsp_problem(problem_input)
    let _ = @scheduling.import_rcpsp_solution(problem, solution_input)
    "{\"ok\":true}"
  } catch {
    error => {
      let message = @json.to_json(error.to_string()).stringify()
      "{\"ok\":false,\"error\":\{message}}"
    }
  }
}

///|
fn main {

}
