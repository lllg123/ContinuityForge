"""Check official PSPLIB downloads and convert the fixed public selection."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

from convert import parse_sm


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(cache: Path, output: Path) -> list[dict]:
    manifest = json.loads(Path(__file__).with_name("selection.json").read_text(encoding="utf-8"))
    output.mkdir(parents=True, exist_ok=True)
    archives = {}
    metadata = {}
    for name, spec in manifest["sets"].items():
        archive_path = cache / f"psplib-{name}.zip"
        metadata_path = cache / f"psplib-{name}-solutions.json"
        if _sha256(archive_path) != spec["archive_sha256"]:
            raise ValueError(f"{name} archive SHA-256 differs from selection.json")
        if _sha256(metadata_path) != spec["metadata_sha256"]:
            raise ValueError(f"{name} metadata SHA-256 differs from selection.json")
        archives[name] = ZipFile(archive_path)
        metadata[name] = json.loads(metadata_path.read_text(encoding="utf-8"))
        if metadata[name]["instance_set"] != name:
            raise ValueError(f"wrong metadata set {name}")
    selected = []
    for spec in manifest["instances"]:
        name = spec["set"]
        raw = archives[name].read(spec["id"])
        converted = parse_sm(raw.decode("latin-1"))
        expected_jobs = 32 if name == "j30" else 62
        if len(converted["tasks"]) != expected_jobs:
            raise ValueError(f"{spec['id']}: unexpected job count")
        matches = [
            row for row in metadata[name]["solutions"]
            if row["parameter"] == spec["parameter"] and row["instance"] == spec["instance"]
        ]
        if len(matches) != 1:
            raise ValueError(f"{spec['id']}: missing or duplicate official reference")
        official = matches[0]
        if official.get("optimal_makespan") != spec["official_optimal"]:
            raise ValueError(f"{spec['id']}: official optimum changed")
        if official.get("upper_bound") != spec["official_upper_bound"]:
            raise ValueError(f"{spec['id']}: official upper bound changed")
        if name == "j60" and official.get("lower_bound") != spec["official_lower_bound"]:
            raise ValueError(f"{spec['id']}: official lower bound changed")
        if bool(official.get("is_proven_optimal")) != (spec["official_optimal"] is not None):
            raise ValueError(f"{spec['id']}: proof status changed")
        output_path = output / f"{spec['id']}.json"
        output_path.write_text(json.dumps(converted, indent=2) + "\n", encoding="utf-8")
        selected.append({
            **spec,
            "source_member_sha256": hashlib.sha256(raw).hexdigest(),
            "converted_file": output_path.name,
            "jobs": len(converted["tasks"]),
            "edges": len(converted["dependencies"]),
            "resources": len(converted["resources"]),
        })
    (output / "provenance.json").write_text(
        json.dumps({"selection": selected}, indent=2) + "\n", encoding="utf-8"
    )
    return selected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    selected = prepare(args.cache, args.output)
    for item in selected:
        print(f"{item['id']}: {item['jobs']} jobs, {item['edges']} edges, "
              f"official optimum={item['official_optimal']}, "
              f"bounds=[{item['official_lower_bound']}, {item['official_upper_bound']}]")


if __name__ == "__main__":
    main()
