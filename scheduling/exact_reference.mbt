///|
/// Small-instance enumeration result. `best` is only proven optimal when the
/// full precedence-feasible activity-list search completed.
pub(all) struct ExactReference {
  best : AnalysisResult?
  proven_optimal : Bool
  explored_nodes : Int
  node_budget : Int
}

///|
priv struct ExactSearchState {
  mut best : AnalysisResult?
  mut explored_nodes : Int
  mut complete : Bool
  budget : Int
}

///|
fn enumerate_activity_lists(
  problem : SchedulingProblem,
  selected : Array[Bool],
  order : Array[Int],
  state : ExactSearchState,
) -> Unit raise SchedulingError {
  if state.explored_nodes >= state.budget {
    state.complete = false
    return
  }
  state.explored_nodes = state.explored_nodes + 1
  if order.length() == problem.tasks.length() {
    let candidate = decode_order(problem, order, "exact-enumeration")
    match state.best {
      None => state.best = Some(candidate)
      Some(current) =>
        if candidate.makespan < current.makespan {
          state.best = Some(candidate)
        }
    }
    return
  }
  for i in 0..<problem.tasks.length() {
    if !selected[i] && prerequisites_selected(problem, i, selected) {
      let next_selected = selected.copy()
      next_selected[i] = true
      let next_order = order.copy()
      next_order.push(i)
      enumerate_activity_lists(problem, next_selected, next_order, state)
    }
  }
}

///|
/// Enumerates precedence-feasible activity lists for at most eight tasks.
/// Node budget counts recursive search nodes, not only complete schedules.
pub fn exact_reference(
  problem : SchedulingProblem,
  node_budget : Int,
) -> ExactReference raise SchedulingError {
  validate_problem(problem)
  if node_budget <= 0 {
    raise SchedulingError::InvalidConstraint(
      "exact search node_budget must be positive",
    )
  }
  if problem.tasks.length() > 8 {
    raise SchedulingError::InvalidConstraint(
      "exact reference supports at most 8 tasks",
    )
  }
  let selected : Array[Bool] = []
  for _ in problem.tasks {
    selected.push(false)
  }
  let state : ExactSearchState = {
    best: None,
    explored_nodes: 0,
    complete: true,
    budget: node_budget,
  }
  enumerate_activity_lists(relaxed_problem(problem), selected, [], state)
  {
    best: state.best,
    proven_optimal: state.complete,
    explored_nodes: state.explored_nodes,
    node_budget,
  }
}

///|
/// Returns the percent gap to a proven optimum for the same problem.
/// A result from an incomplete search cannot be used as the denominator.
pub fn optimality_gap_percent(
  candidate : AnalysisResult,
  reference : ExactReference,
) -> Double raise SchedulingError {
  if !reference.proven_optimal {
    raise SchedulingError::InvalidConstraint("exact reference is incomplete")
  }
  let optimum = match reference.best {
    Some(value) => value.makespan
    None => abort("complete exact search has no result")
  }
  if candidate.makespan < optimum {
    raise SchedulingError::InvalidSchedule(
      "candidate makespan is below proven optimum",
    )
  }
  if optimum == 0 {
    if candidate.makespan == 0 {
      return 0.0
    }
    raise SchedulingError::InvalidSchedule(
      "nonzero candidate for zero-duration optimum",
    )
  }
  (candidate.makespan - optimum).to_double() * 100.0 / optimum.to_double()
}
