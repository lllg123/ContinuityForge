"""Convert an unmodified official PSPLIB single-mode .sm file to RCPSP v2.

The source archive is downloaded separately; this repository does not bundle
PSPLIB instance files or redistribute the full dataset.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from zipfile import ZipFile


def _integer_after(text: str, label: str) -> int:
    match = re.search(rf"^\s*{re.escape(label)}\s*:\s*(\d+)", text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing {label}")
    return int(match.group(1))


def _section_rows(text: str, heading: str) -> list[list[int]]:
    part = text.split(heading + ":", 1)
    if len(part) != 2:
        raise ValueError(f"missing section {heading}")
    block = part[1].split("********", 1)[0]
    return [
        [int(word) for word in line.split()]
        for line in block.splitlines()
        if re.fullmatch(r"\s*\d+(?:\s+\d+)*\s*", line)
    ]


def parse_sm(text: str) -> dict:
    jobs = _integer_after(text, "jobs (incl. supersource/sink )")
    renewable = _integer_after(text, "- renewable")
    nonrenewable = _integer_after(text, "- nonrenewable")
    doubly = _integer_after(text, "- doubly constrained")
    if nonrenewable or doubly or renewable < 1:
        raise ValueError("instance is outside single-mode renewable-only subset")
    if _integer_after(text, "projects") != 1:
        raise ValueError("only single-project instances are supported")
    project_info = _section_rows(text, "PROJECT INFORMATION")
    if len(project_info) != 1 or len(project_info[0]) != 6 or project_info[0][2] != 0:
        raise ValueError("nonzero project release or malformed project information")
    precedences = _section_rows(text, "PRECEDENCE RELATIONS")
    requests = _section_rows(text, "REQUESTS/DURATIONS")
    capacities = _section_rows(text, "RESOURCEAVAILABILITIES")
    if len(precedences) != jobs or len(requests) != jobs or len(capacities) != 1:
        raise ValueError("truncated or extra PSPLIB rows")
    if len(capacities[0]) != renewable or any(cap <= 0 for cap in capacities[0]):
        raise ValueError("invalid renewable capacities")
    resources = [
        {"id": f"R{index + 1}", "capacity": capacity}
        for index, capacity in enumerate(capacities[0])
    ]
    task_by_id = {}
    for row in requests:
        if len(row) != renewable + 3:
            raise ValueError("duration/request row has wrong width")
        job, mode, duration, *amounts = row
        if mode != 1 or job in task_by_id or duration < 0:
            raise ValueError("unexpected mode, duplicate job, or negative duration")
        demands = [
            {"resource_id": f"R{index + 1}", "amount": amount}
            for index, amount in enumerate(amounts)
            if amount > 0
        ]
        if any(amount < 0 or amount > capacities[0][index] for index, amount in enumerate(amounts)):
            raise ValueError("invalid job demand")
        if duration == 0 and demands:
            raise ValueError("zero-duration milestone has resource demand")
        task_by_id[job] = {
            "id": str(job), "duration": duration, "priority": 0,
            "demands": demands, "release_time": 0,
        }
    if set(task_by_id) != set(range(1, jobs + 1)):
        raise ValueError("missing or unexpected job number")
    dependencies = []
    seen_edges = set()
    seen_precedence_jobs = set()
    for row in precedences:
        if len(row) < 3:
            raise ValueError("precedence row is incomplete")
        job, modes, count, *successors = row
        if modes != 1 or count != len(successors) or job not in task_by_id:
            raise ValueError("invalid single-mode precedence row")
        if job in seen_precedence_jobs:
            raise ValueError("duplicate precedence job row")
        seen_precedence_jobs.add(job)
        for successor in successors:
            edge = (job, successor)
            if successor not in task_by_id or edge in seen_edges or job == successor:
                raise ValueError("invalid or duplicate precedence edge")
            seen_edges.add(edge)
            dependencies.append({"task_id": str(successor), "prerequisite_id": str(job)})
    return {
        "schema_version": "continuityforge.rcpsp.v2",
        "time_unit": "PSPLIB time unit",
        "resources": resources,
        "tasks": [task_by_id[job] for job in range(1, jobs + 1)],
        "dependencies": dependencies,
        "solve_options": {
            "algorithm": "budgeted-local-search",
            "search_budget": 30,
            "time_limit_ms": 5000,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="official j30.sm.zip / j60.sm.zip / j90.sm.zip")
    parser.add_argument("instance", help="exact archive member, e.g. j301_1.sm")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with ZipFile(args.archive) as archive:
        if args.instance not in archive.namelist():
            raise ValueError(f"instance {args.instance!r} absent from archive")
        raw = archive.read(args.instance).decode("latin-1")
    converted = parse_sm(raw)
    args.output.write_text(json.dumps(converted, indent=2) + "\n", encoding="utf-8")
    print(f"{args.instance}: {len(converted['tasks'])} jobs, "
          f"{len(converted['dependencies'])} edges, "
          f"{len(converted['resources'])} renewable resources")


if __name__ == "__main__":
    main()
