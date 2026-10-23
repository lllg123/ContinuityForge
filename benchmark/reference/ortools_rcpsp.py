"""Independent CP-SAT reference for the canonical ContinuityForge RCPSP v2 JSON.

Run from the repository root with a pinned OR-Tools environment. This script
never calls MoonBit's heuristic; it models the same constraints directly.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import ortools
from ortools.sat.python import cp_model

INT_MAX = 2_147_483_647


def solve(problem: dict, time_limit_seconds: float) -> dict:
    if problem.get("schema_version") != "continuityforge.rcpsp.v2":
        raise ValueError("unsupported schema_version")
    if time_limit_seconds <= 0:
        raise ValueError("time limit must be positive")
    tasks = problem["tasks"]
    resources = problem["resources"]
    edges = problem["dependencies"]
    task_by_id = {task["id"]: task for task in tasks}
    resource_by_id = {resource["id"]: resource for resource in resources}
    if len(task_by_id) != len(tasks) or len(resource_by_id) != len(resources):
        raise ValueError("duplicate task or resource id")
    if not problem.get("time_unit") or any(
        not resource["id"] or resource["capacity"] <= 0 for resource in resources
    ):
        raise ValueError("invalid time unit or renewable resource")
    for task in tasks:
        if not task["id"] or task["duration"] < 0 or task["release_time"] < 0:
            raise ValueError("invalid task id, duration, or release time")
        if task["duration"] > INT_MAX - task["release_time"]:
            raise ValueError("task time overflows MoonBit Int")
        if task.get("deadline", INT_MAX) < task["release_time"]:
            raise ValueError("deadline precedes release")
        if task["duration"] == 0 and task["demands"]:
            raise ValueError("zero-duration milestone cannot use resources")
        if len({d["resource_id"] for d in task["demands"]}) != len(task["demands"]):
            raise ValueError("duplicate resource demand")
        for demand in task["demands"]:
            resource = resource_by_id.get(demand["resource_id"])
            if resource is None or not 0 < demand["amount"] <= resource["capacity"]:
                raise ValueError("unknown resource or invalid demand")
    if problem.get("target_makespan", 0) < 0:
        raise ValueError("negative target makespan")
    if len({(edge["task_id"], edge["prerequisite_id"]) for edge in edges}) != len(edges):
        raise ValueError("duplicate precedence edge")
    for edge in edges:
        if (edge["task_id"] not in task_by_id or edge["prerequisite_id"] not in task_by_id
                or edge["task_id"] == edge["prerequisite_id"]):
            raise ValueError("invalid precedence edge")
    horizon = max((task["release_time"] for task in tasks), default=0) + sum(
        task["duration"] for task in tasks
    )
    if horizon > INT_MAX:
        raise ValueError("horizon exceeds MoonBit Int range")
    model = cp_model.CpModel()
    starts = {}
    ends = {}
    intervals = {}
    for task in tasks:
        task_id = task["id"]
        duration = task["duration"]
        release = task["release_time"]
        if duration < 0 or release < 0:
            raise ValueError("negative duration or release time")
        starts[task_id] = model.new_int_var(release, horizon, f"start_{task_id}")
        ends[task_id] = model.new_int_var(release, horizon, f"end_{task_id}")
        intervals[task_id] = model.new_interval_var(
            starts[task_id], duration, ends[task_id], f"interval_{task_id}"
        )
        if "deadline" in task:
            model.add(ends[task_id] <= task["deadline"])
    for edge in edges:
        model.add(starts[edge["task_id"]] >= ends[edge["prerequisite_id"]])
    for resource in resources:
        relevant_intervals = []
        amounts = []
        for task in tasks:
            demands = task["demands"]
            for demand in demands:
                if demand["resource_id"] == resource["id"]:
                    relevant_intervals.append(intervals[task["id"]])
                    amounts.append(demand["amount"])
        if relevant_intervals:
            model.add_cumulative(relevant_intervals, amounts, resource["capacity"])
    makespan = model.new_int_var(0, horizon, "makespan")
    for task in tasks:
        model.add(makespan >= ends[task["id"]])
    if "target_makespan" in problem:
        model.add(makespan <= problem["target_makespan"])
    model.minimize(makespan)

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = time_limit_seconds
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = 20261023
    status_code = solver.solve(model)
    status = {
        cp_model.OPTIMAL: "OPTIMAL",
        cp_model.FEASIBLE: "FEASIBLE",
        cp_model.INFEASIBLE: "INFEASIBLE",
        cp_model.UNKNOWN: "UNKNOWN",
    }.get(status_code, "UNKNOWN")
    feasible = status in ("OPTIMAL", "FEASIBLE")
    schedule = [
        {
            "task_id": task["id"],
            "start": solver.value(starts[task["id"]]),
            "finish": solver.value(ends[task["id"]]),
        }
        for task in tasks
    ] if feasible else []
    result = {
        "schema_version": "continuityforge.rcpsp.solution.v2",
        "status": status,
        "algorithm": "ortools-cp-sat",
        "schedule": schedule,
        "candidates_evaluated": 0,
        "accepted_moves": 0,
        "budget": 0,
        "elapsed_ms": round(solver.wall_time * 1000),
        "diagnostic": f"OR-Tools {ortools.__version__}; 1 worker; {time_limit_seconds:g}s limit",
    }
    if feasible:
        result["makespan"] = max((entry["finish"] for entry in schedule), default=0)
    if status in ("OPTIMAL", "FEASIBLE", "UNKNOWN"):
        bound = solver.best_objective_bound
        if math.isfinite(bound) and bound >= 0:
            result["lower_bound"] = math.ceil(bound - 1e-9)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("problem", type=Path)
    parser.add_argument("--time-limit", type=float, help="override v2 solve_options.time_limit_ms")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    problem = json.loads(args.problem.read_text(encoding="utf-8"))
    time_limit = args.time_limit
    if time_limit is None:
        time_limit = problem.get("solve_options", {}).get("time_limit_ms", 5000) / 1000
    result = solve(problem, time_limit)
    encoded = json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
