#!/usr/bin/env python3
"""Stage frozen same-input schematic variants and their EDA dependency closure."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[2]
EDA = ROOT.parent / "eda"
FROZEN = ROOT / "experiments/schematic/fixtures"
STAGE = ROOT / ".tmp/full-svg-benchmark-20260921/projects"
PROVENANCE = Path(__file__).with_name("fixture-provenance.json")

CIRCUIT = "straps-synth-lmx2595.sexp"
PINOUT = "lmx2595rhar.sexp"
INTERFACE = "spi.sexp"

# The module imports lmx2595rhar and cap-0603 explicitly. The other passive
# families are auto-loaded by NetLisp, but the live project shadows the bundled
# definitions and part catalogs; copying them preserves the actual resolution
# used by the source rather than silently falling back to the executable bundle.
DEPENDENCIES = (
    "lib/components/lmx2595rhar.sexp",
    "lib/components/cap-0402.sexp",
    "lib/components/cap-0603.sexp",
    "lib/components/res-0402.sexp",
    "lib/components/ind-0402.sexp",
    "lib/parts/cap-0402.sexp",
    "lib/parts/cap-0603.sexp",
    "lib/parts/res-0402.sexp",
    "lib/parts/ind-0402.sexp",
)

VARIANTS = {
    "fixture": (),
    "changed-net": (("LMX_CE", "LMX_CE_BENCH"),),
    "changed-value": (("390pF", "470pF"),),
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT.parent))


def put(project: Path, destination: str, data: bytes, source: Path, files: list[dict], transform: str | None = None) -> None:
    target = project / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    entry = {
        "destination": str(target.relative_to(project)),
        "source": relative(source),
        "source_sha256": digest(source.read_bytes()),
        "staged_sha256": digest(data),
        "bytes": len(data),
    }
    if transform:
        entry["transform"] = transform
    files.append(entry)


def transformed_source(name: str) -> tuple[bytes, list[str]]:
    data = (FROZEN / CIRCUIT).read_text()
    applied = []
    for before, after in VARIANTS[name]:
        count = data.count(before)
        if name == "changed-value" and count != 1:
            raise RuntimeError(f"expected one {before!r}, found {count}")
        if name == "changed-net" and count < 2:
            raise RuntimeError(f"expected connected uses of {before!r}, found {count}")
        data = data.replace(before, after)
        applied.append(f"replace every {before!r} with {after!r} ({count} occurrences)")
    return data.encode(), applied


def main() -> None:
    STAGE.mkdir(parents=True, exist_ok=True)
    records = {}
    for name in VARIANTS:
        project = STAGE / name
        if project.exists():
            shutil.rmtree(project)
        project.mkdir(parents=True)
        files: list[dict] = []
        circuit, transformations = transformed_source(name)
        transform = "; ".join(transformations) if transformations else None
        put(project, f"lib/modules/{CIRCUIT}", circuit, FROZEN / CIRCUIT, files, transform)
        put(project, f"lib/pinouts/{PINOUT}", (FROZEN / PINOUT).read_bytes(), FROZEN / PINOUT, files)
        put(project, f"lib/interfaces/{INTERFACE}", (FROZEN / INTERFACE).read_bytes(), FROZEN / INTERFACE, files)
        for dependency in DEPENDENCIES:
            source = EDA / "projects/designs" / dependency
            put(project, dependency, source.read_bytes(), source, files)
        records[name] = {
            "project": str(project.relative_to(ROOT)),
            "circuit": f"lib/modules/{CIRCUIT}",
            "pinout": f"lib/pinouts/{PINOUT}",
            "interface": f"lib/interfaces/{INTERFACE}",
            "transformations": transformations,
            "files": files,
        }
    evidence = {
        "schema": "full-svg-fixtures-v1",
        "source_policy": "frozen benchmark documents plus the minimal live EDA component and part resolution closure; no EDA files modified",
        "expected_model": {"components": 30, "connected_pins": 95, "nets": 34, "ports": 9, "visible_ic_pins": 37, "passives": 29},
        "variants": records,
    }
    PROVENANCE.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({name: records[name]["project"] for name in records}, indent=2))


if __name__ == "__main__":
    main()
