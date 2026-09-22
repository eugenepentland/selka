#!/usr/bin/env python3
"""Gate one frozen design of the sexpr reader against the port's own oracle.

A cascading-benefit arm (``designs/B``, ``designs/P1``, ``designs/P2``, or a
reference patch applied to a copy of one) is only eligible for the maintainer
runs when it passes the same three checks the port itself passes:

1. the guest suite under ``<arm>/tests`` -- 79 tests, zero failures;
2. the 17 byte-identical goldens in ``experiments/sexpr-port/golden/`` -- the
   real Zig printer is the oracle, so this is an independent check, not
   agreement between arms;
3. the differential census against ``experiments/sexpr-port/reference_parse.py``
   over the in-repo fixtures, and over the two ~185 kB EDA boards with
   ``--large``.

The three checks are the port's own gate (``run_all.sh``); this script runs them
against an arbitrary arm directory instead of the port directory, so a design
that has moved code around is still measured by the same oracle.

Usage:
    python3 experiments/cascade/arm_gate.py experiments/cascade/designs/B
    python3 experiments/cascade/arm_gate.py <copy> --label T1 --json out.json
    python3 experiments/cascade/arm_gate.py <copy> --skip-large
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PORT = REPO / "experiments" / "sexpr-port"
GOLDEN = PORT / "golden"
FIELDS = ["forms", "nodes", "atoms", "strings", "ints", "floats", "measures", "max_depth"]
_FROZEN = HERE / "tools" / "bin" / "mylang"
DEFAULT_BIN = _FROZEN if _FROZEN.is_file() else (REPO / "zig-out" / "bin" / "mylang")
sys.dont_write_bytecode = True
sys.path.insert(0, str(PORT))
import reference_parse  # noqa: E402

IN_REPO_FIXTURES = [
    PORT / "fixtures" / "units.sexp",
    REPO / "experiments" / "schematic" / "fixtures" / "spi.sexp",
    REPO / "experiments" / "schematic" / "fixtures" / "lmx2595rhar.sexp",
    REPO / "experiments" / "schematic" / "fixtures" / "straps-synth-lmx2595.sexp",
]
LARGE_FIXTURES = [
    REPO.parent / "eda/projects/designs/lib/modules/poe-pd-flyback-tps23757.sexp",
    REPO.parent / "eda/projects/designs/src/boards/remora-rf/remora-rf.sexp",
]
PASSED = re.compile(r"(\d+) passed, (\d+) cached, (\d+) failed")


def run(argv: list[str], cwd: Path) -> subprocess.CompletedProcess:
    """Run from a scratch directory so the compiler's cache never lands in an arm."""
    cwd.mkdir(parents=True, exist_ok=True)
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True)


def check_tests(binary: Path, arm: Path, expected: int | None) -> dict:
    """Run the arm's guest suite and require exactly the pinned coverage.

    "Some tests passed" is not a gate: an arm that quietly lost tests, or a run
    that selected a subset, would otherwise certify itself.
    """
    result = run([str(binary), "test", str(arm / "tests")], cwd=HERE / ".cache" / "tests")
    match = PASSED.search(result.stdout)
    fresh = int(match.group(1)) if match else 0
    cached = int(match.group(2)) if match else 0
    failed = int(match.group(3)) if match else -1
    total = fresh + cached
    ok = result.returncode == 0 and failed == 0 and total > 0
    if expected is not None:
        ok = ok and total == expected
    return {
        "passed": total,
        "fresh": fresh,
        "cached": cached,
        "failed": failed,
        "expected": expected,
        "pinned": expected is not None,
        "exit": result.returncode,
        "ok": ok,
        "stderr_tail": result.stderr.strip().splitlines()[-3:],
    }


def check_goldens(binary: Path, arm: Path, skip_large: bool, expected: int | None) -> dict:
    """Byte-compare the arm's renderings with the Zig goldens, one stripped newline."""
    manifest = GOLDEN / "manifest.tsv"
    large = {path.resolve() for path in LARGE_FIXTURES}
    rows = []
    for line in manifest.read_text().splitlines():
        if not line.strip():
            continue
        name, _, source = line.partition("\t")
        path = Path(source.strip())
        path = path if path.is_absolute() else REPO / path
        if skip_large and path.resolve() in large:
            continue
        rows.append((name.strip(), path))
    failures = []
    for name, source in rows:
        golden = (GOLDEN / f"{name}.txt").read_bytes()
        result = run([str(binary), "run", str(arm / "main.my"), "--", str(source), "--render"], cwd=HERE / ".cache" / "goldens")
        captured = result.stdout.encode()
        if result.returncode != 0:
            failures.append({"name": name, "reason": f"exit {result.returncode}", "stderr": result.stderr.strip()[:200]})
            continue
        stripped = captured[:-1] if captured.endswith(b"\n") else captured
        if stripped != golden:
            failures.append({"name": name, "reason": "bytes differ", "expected": len(golden), "actual": len(stripped)})
    ok = not failures
    if expected is not None:
        # A shortened manifest is missing coverage, not passing it.
        ok = ok and len(rows) == expected
    return {"passed": len(rows) - len(failures), "failed": len(failures), "expected": expected,
            "ok": ok, "failures": failures}


def check_reference(binary: Path, arm: Path, fixtures: list[Path]) -> dict:
    """Compare the arm's census with the independent Python reader."""
    rows = []
    for path in fixtures:
        if not path.exists():
            rows.append({"fixture": str(path), "status": "missing"})
            continue
        reference = reference_parse.parse_file(path)
        if not reference["ok"]:
            rows.append({"fixture": str(path), "status": "reference-rejected"})
            continue
        result = run([str(binary), "run", str(arm / "main.my"), "--", str(path)], cwd=HERE / ".cache" / "reference")
        if result.returncode != 0:
            rows.append({"fixture": str(path), "status": "mylang-failed", "stderr": result.stderr.strip()[:200]})
            continue
        stats = {}
        for pair in result.stdout.strip().split():
            key, _, value = pair.partition("=")
            if key:
                stats[key] = float(value) if key == "value_sum" else int(value)
        differing = [field for field in FIELDS if reference.get(field, 0) != stats.get(field, 0)]
        if abs(reference.get("value_sum", 0.0) - stats.get("value_sum", 0.0)) > 1e-9 * max(1.0, abs(reference.get("value_sum", 1.0))):
            differing.append("value_sum")
        rows.append({"fixture": path.name, "status": "ok" if not differing else "mismatch", "differing": differing})
    ok = all(row["status"] == "ok" for row in rows)
    missing = [row["fixture"] for row in rows if row["status"] == "missing"]
    return {"passed": sum(1 for row in rows if row["status"] == "ok"), "rows": rows, "ok": ok, "missing": missing}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("arm", type=Path, help="arm directory holding main.my, sexpr/ and tests/")
    parser.add_argument("--bin", type=Path, default=DEFAULT_BIN, help="compiler to use (default zig-out/bin/mylang)")
    parser.add_argument("--label", default="", help="name recorded in the report (default: the arm directory name)")
    parser.add_argument("--json", type=Path, help="also write the report here")
    parser.add_argument("--skip-large", action="store_true", help="skip the two ~185 kB EDA boards")
    parser.add_argument("--expect-tests", type=int, default=None,
                        help="required guest-test count; without it the gate is unpinned and refuses to certify")
    parser.add_argument("--expect-goldens", type=int, default=17, help="required golden count (default 17)")
    parser.add_argument("--allow-unpinned", action="store_true", help="record an unpinned gate instead of refusing")
    args = parser.parse_args()
    arm = args.arm.resolve()
    if not (arm / "main.my").is_file():
        print(f"arm_gate: {arm} has no main.my", file=sys.stderr)
        return 2
    fixtures = list(IN_REPO_FIXTURES) + ([] if args.skip_large else [p for p in LARGE_FIXTURES if p.exists()])
    if args.expect_tests is None and not args.allow_unpinned:
        print("arm_gate: refusing to certify an unpinned gate; pass --expect-tests N "
              "(B and P1: 79, P2: 127) or --allow-unpinned to record coverage as unpinned", file=sys.stderr)
        return 2
    report = {
        "version": 1,
        "label": args.label or arm.name,
        "pinned": args.expect_tests is not None,
        "arm": str(arm),
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "compiler": str(args.bin),
        "tests": check_tests(args.bin, arm, args.expect_tests),
        "goldens": check_goldens(args.bin, arm, args.skip_large, args.expect_goldens),
        "reference": check_reference(args.bin, arm, fixtures),
    }
    report["passed"] = all(report[key]["ok"] for key in ("tests", "goldens", "reference"))
    text = json.dumps(report, indent=2) + "\n"
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(text)
    tests, goldens, reference = report["tests"], report["goldens"], report["reference"]
    print(f"tests     {tests['passed']} passed, {tests['failed']} failed")
    print(f"goldens   {goldens['passed']}/{goldens['passed'] + goldens['failed']} passed")
    print(f"reference {reference['passed']} fixtures agree")
    for row in reference["rows"]:
        if row["status"] not in ("ok", "missing"):
            print(f"  {row['fixture']}: {row['status']} {row.get('differing', '')}")
    for failure in goldens.get("failures", []):
        print(f"  golden {failure['name']}: {failure['reason']}")
    print(f"gate      {'PASS' if report['passed'] else 'FAIL'}  ({report['label']})")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
