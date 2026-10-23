"""Small CP-SAT regression gate for the three complete v2 scenarios."""

from __future__ import annotations

import json
from pathlib import Path

from ortools_rcpsp import solve

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    cases = [
        ("ci", 11, "ci-deadline-fail"),
        ("recovery", 8, "recovery-capacity-fail"),
        ("project", 11, "project-deadline-fail"),
    ]
    for name, expected, failure in cases:
        folder = ROOT / "examples" / "rcpsp"
        valid = json.loads((folder / f"{name}.json").read_text(encoding="utf-8"))
        invalid = json.loads((folder / f"{failure}.json").read_text(encoding="utf-8"))
        optimal = solve(valid, 5.0)
        no_solution = solve(invalid, 5.0)
        assert optimal["status"] == "OPTIMAL" and optimal["makespan"] == expected, (name, optimal)
        assert no_solution["status"] == "INFEASIBLE", (failure, no_solution)
        print(f"{name}: OPTIMAL {expected}; {failure}: INFEASIBLE")


if __name__ == "__main__":
    main()
