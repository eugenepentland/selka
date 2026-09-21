#!/usr/bin/env python3
"""Cold-cache build cost and binary size for both backend arms.

    qualify_cost.py [--work DIR] [--rounds N] [--json OUT]

Every round builds the same entry — the sexpr-port benchmark closure — from a
cache directory that is deleted first, so the number includes the whole
frontend, every unit's code generation, the runtime archive, the assembler and
the link.  `--report` splits that into the driver's own phases, which is what
tells a code-generation cost apart from a frontend one.  Both arms are built
with identical flags; the adapter's own recipe hash is recorded so a later edit
to the translator cannot be mistaken for a compiler change.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import shutil
import subprocess
import sys
import time
from pathlib import Path

from qualify_identity import identity

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ADAPTER = HERE / "qbe_llvm.py"
PORT = "experiments/sexpr-port/main.my"


def one_build(mylang, arm, tool, work, round_index):
    """One cold-cache build, returning its phases, wall time and binary size."""
    cache = work / f"cache-{arm}-{round_index}"
    shutil.rmtree(cache, ignore_errors=True)
    binary = work / f"port-{arm}-{round_index}"
    command = [str(mylang), "build", PORT, "-o", str(binary), "--mode=ReleaseFast",
               "--keep-symbols", "--report", f"--cache-dir={cache}"]
    if tool is not None:
        command.append(f"--qbe={tool}")
    start = time.perf_counter()
    done = subprocess.run(command, capture_output=True, text=True, timeout=3600, cwd=REPO)
    wall = (time.perf_counter() - start) * 1000.0
    record = {"arm": arm, "round": round_index, "wall_ms": round(wall, 1),
              "status": done.returncode, "binary_bytes": None, "report": None,
              "stderr": done.stderr[-600:]}
    if done.returncode == 0:
        record["binary_bytes"] = binary.stat().st_size
        # `--report` writes its work report to stdout; `--timings=json` writes
        # JSON Lines to stderr.  Read both so the phase split survives either.
        for line in (*done.stdout.splitlines(), *done.stderr.splitlines()):
            line = line.strip()
            if line.startswith('{"version":"qbe-build-v1"'):
                report = json.loads(line)
                record["report"] = {key: report[key] for key in
                                    ("frontend_seconds", "codegen_seconds", "link_seconds",
                                     "native_seconds", "compiled_functions", "reused_functions")
                                    if key in report}
        receipt = Path(str(binary) + ".qbe-manifest.json")
        if receipt.exists():
            manifest = json.loads(receipt.read_text())
            runtime = Path(manifest["runtime_object"])
            record["runtime_sha256"] = hashlib.sha256(runtime.read_bytes()).hexdigest()
            record["runtime_bytes"] = runtime.stat().st_size
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mylang", default=str(REPO / "zig-out" / "bin" / "mylang"))
    parser.add_argument("--work", default="/tmp/llvm-qual-cost")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--json", dest="out")
    options = parser.parse_args()
    if options.rounds < 3:
        parser.error("--rounds must be at least 3 for a median")
    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)

    report = {"tool": "qualify_cost.py", "entry": PORT, "rounds": options.rounds,
              "mode": "ReleaseFast", "flags": "--keep-symbols",
              "compiler_sha256": hashlib.sha256(Path(options.mylang).read_bytes()).hexdigest(),
              "identity_start": identity(options.mylang),
              "adapter_sources": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in sorted(HERE.glob("*.py"))},
              "samples": []}
    # Interleaved so a drifting machine cannot favour one arm's whole batch.
    for round_index in range(options.rounds):
        for arm, tool in (("qbe", None), ("llvm", str(ADAPTER))):
            record = one_build(Path(options.mylang), arm, tool, work, round_index)
            report["samples"].append(record)
            print(f"round {round_index} {arm:5s} {record['wall_ms']:9.1f} ms  "
                  f"binary={record['binary_bytes']}  {record['report']}", flush=True)

    summary = {}
    for arm in ("qbe", "llvm"):
        records = [record for record in report["samples"] if record["arm"] == arm]
        walls = [record["wall_ms"] for record in records]
        sizes = [record["binary_bytes"] for record in records if record["binary_bytes"]]
        summary[arm] = {"wall_ms_median": statistics.median(walls), "wall_ms": walls,
                        "binary_bytes_median": statistics.median(sizes) if sizes else None,
                        "binary_bytes": sizes}
        for phase in ("frontend_seconds", "codegen_seconds", "link_seconds", "native_seconds"):
            values = [record["report"][phase] for record in records
                      if record["report"] and phase in record["report"]]
            if values:
                summary[arm][f"{phase}_median"] = statistics.median(values)
    report["summary"] = summary
    report["identity_end"] = identity(options.mylang)
    qbe, llvm = summary["qbe"], summary["llvm"]
    if qbe["wall_ms_median"] and llvm["wall_ms_median"]:
        report["ratio_llvm_over_qbe"] = llvm["wall_ms_median"] / qbe["wall_ms_median"]
    if qbe.get("codegen_seconds_median") and llvm.get("codegen_seconds_median"):
        report["codegen_ratio"] = llvm["codegen_seconds_median"] / qbe["codegen_seconds_median"]
    print()
    for arm, values in summary.items():
        print(f"{arm:5s} median {values['wall_ms_median']:9.1f} ms  "
              f"codegen {values.get('codegen_seconds_median')} s  "
              f"binary {values['binary_bytes_median']} B")
    print(f"LLVM/QBE wall ratio {report.get('ratio_llvm_over_qbe')}, "
          f"codegen ratio {report.get('codegen_ratio')}")
    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
