#!/usr/bin/env python3
"""Scan-only floor benchmark: hand-written assembly and hand-written QBE IR.

The six-phase comparison answers "which implementation is fast"; this answers
"how fast can the `scan` phase be at all". It measures the same 927,415-byte
input with the same process-wall methodology, but only the scan workload, and it
adds implementations that exist purely to bracket the floor:

  asm startup only   static syscall-only binary that exits          (start-up)
  asm read only      open + read the file, count nothing             (+ I/O)
  asm scalar         read + byte-at-a-time loop                      (+ scan)
  asm sse2           read + 16-byte SSE2 blocks, unrolled 4x
  asm avx2           read + 32-byte AVX2 blocks, unrolled 2x
  qbe ir scalar      hand-written QBE IL, byte-at-a-time loop
  qbe ir swar        hand-written QBE IL, 8 bytes/iteration with 64-bit SWAR

plus the existing Zig / mylang / Go / Python scan columns for reference. The
asm and QBE sources are in `asm/` and `qbe/`; every scanner prints the same
`bytes=<n> delims=<m>` line and is checked against `zig-bench --scan`.

Usage:
  python3 experiments/sexpr-audit/scan_floor.py [--runs N]
Writes evidence/scan-floor.json; `scan_floor_charts.py` draws the figure.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

import compare_impls as base

AUDIT = base.AUDIT
REPO = base.REPO
WORK = base.WORK
EVIDENCE = base.EVIDENCE
PYDIR = base.PYDIR
ASM_DIR = AUDIT / "asm"
QBE_DIR = AUDIT / "qbe"
ZIGCTL_DIR = AUDIT / "zigctl"
QBE = REPO / "zig-out/bin/qbe"
CC = shutil.which("cc") or "cc"
AS = shutil.which("as") or "as"
LD = shutil.which("ld") or "ld"
TASKSET = base.TASKSET
CORE = base.CORE

_WORK_RE = re.compile(r"work_ms=([0-9.]+)")
_IMPORT_RE = re.compile(r"import_ms=([0-9.]+)")

# label -> (argv template, expected digest or None). "{input}" marks where the
# input path goes; `None` means the scanner does not read the input.
SCANNERS = [
    ("asm startup only", [str(WORK / "asm-exit")], None),
    ("asm read only", [str(WORK / "asm-scan-0"), "{input}"], "baseline"),
    ("asm scalar", [str(WORK / "asm-scan-1"), "{input}"], "real"),
    ("asm sse2", [str(WORK / "asm-scan-2"), "{input}"], "real"),
    ("asm avx2", [str(WORK / "asm-scan-3"), "{input}"], "real"),
    ("qbe ir scalar", [str(WORK / "qbe-scan"), "{input}"], "real"),
    ("qbe ir swar", [str(WORK / "qbe-swar"), "{input}"], "real"),
    ("zig ReleaseFast", [str(base.ZIG_OUT["zig ReleaseFast"]), "{input}", "--scan"], "real"),
    ("zig ReleaseSafe", [str(base.ZIG_OUT["zig ReleaseSafe"]), "{input}", "--scan"], "real"),
    ("mylang ReleaseFast", [str(WORK / "my-scan"), "{input}"], "real"),
    ("zig llvm scalar", [str(WORK / "zig-scan-scalar"), "{input}"], "real"),
    ("zig llvm swar", [str(WORK / "zig-scan-swar"), "{input}"], "real"),
    ("go", [str(base.GO_OUT), "{input}", "--scan"], "real"),
    ("python pure", None, "real"),
    ("python + libs", None, "real"),
    ("python tuned", None, "real"),
]
PY_SCRIPTS = {
    "python pure": "sexpr_pure.py",
    "python + libs": "sexpr_np.py",
    "python tuned": "sexpr_tuned.py",
}


def build_asm(force: bool) -> None:
    (WORK / "asm").mkdir(parents=True, exist_ok=True)
    jobs = [("exit", ASM_DIR / "exit.s", []),
            ("scan-0", ASM_DIR / "scan.s", ["--defsym", "VARIANT=0"]),
            ("scan-1", ASM_DIR / "scan.s", ["--defsym", "VARIANT=1"]),
            ("scan-2", ASM_DIR / "scan.s", ["--defsym", "VARIANT=2"]),
            ("scan-3", ASM_DIR / "scan.s", ["--defsym", "VARIANT=3"])]
    for name, source, flags in jobs:
        obj = WORK / "asm" / f"{name}.o"
        out = WORK / ("asm-exit" if name == "exit" else f"asm-{name}")
        if not force and out.exists() and out.stat().st_mtime >= source.stat().st_mtime:
            continue
        subprocess.run([AS, *flags, "-o", str(obj), str(source)], check=True)
        subprocess.run([LD, "-s", "-o", str(out), str(obj)], check=True)
        print(f"  built asm {name}")


def build_qbe(force: bool) -> None:
    jobs = [("scan", QBE_DIR / "scan.ssa", "qbe-scan"),
            ("swar", QBE_DIR / "scan_swar.ssa", "qbe-swar")]
    for name, source, binary in jobs:
        out = WORK / binary
        if not force and out.exists() and out.stat().st_mtime >= source.stat().st_mtime:
            continue
        asm = WORK / f"{binary}.s"
        with asm.open("wb") as handle:
            subprocess.run([str(QBE), str(source), "-o", "-"], stdout=handle, check=True)
        subprocess.run([CC, "-static", "-o", str(out), str(asm)], check=True)
        print(f"  built qbe {name}")


def build_zigctl(force: bool) -> None:
    """Build the Zig controls: the same two loops, same read/print path, LLVM."""
    env = base.tool_env()
    for variant in ("scalar", "swar"):
        source = ZIGCTL_DIR / f"scan_{variant}.zig"
        out = WORK / f"zig-scan-{variant}"
        if not force and out.exists() and out.stat().st_mtime >= source.stat().st_mtime:
            continue
        proc = subprocess.run(
            ["zig", "build-exe", "-OReleaseFast", f"-femit-bin={out}", str(source)],
            capture_output=True, text=True, env=env)
        if proc.returncode != 0:
            raise SystemExit(f"zig control {variant} failed:\n{proc.stdout}\n{proc.stderr}")
        print(f"  built zig control {variant}")


def argv_for(label: str, template, input_path: Path, python: Path) -> list:
    if label in PY_SCRIPTS:
        return [str(python), str(PYDIR / PY_SCRIPTS[label]), str(input_path), "--scan"]
    return [str(input_path) if arg == "{input}" else arg for arg in template]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=41)
    ap.add_argument("--input", default=None)
    ap.add_argument("--rebuild", action="store_true")
    args = ap.parse_args()

    input_path = Path(args.input) if args.input else base.ensure_input()
    python = base.find_python()
    print(f"input {input_path} ({input_path.stat().st_size} bytes)")
    print("building ...")
    base.build_zig(args.rebuild)
    base.build_mylang(args.rebuild)
    base.build_go(args.rebuild)
    build_asm(args.rebuild)
    build_qbe(args.rebuild)
    build_zigctl(args.rebuild)

    reference = hashlib.sha256(subprocess.run(
        [str(base.ZIG_OUT["zig ReleaseFast"]), str(input_path), "--scan"],
        capture_output=True).stdout).hexdigest()[:16]

    samples: dict = {}
    works: dict = {}
    imports: dict = {}
    digests: dict = {}
    loadavg = [os.getloadavg()]
    for _ in range(args.runs):
        for label, template, expected in SCANNERS:
            command = [TASKSET, "-c", CORE,
                       *argv_for(label, template, input_path, python)]
            start = time.perf_counter()
            proc = subprocess.run(command, capture_output=True, text=True)
            elapsed = (time.perf_counter() - start) * 1000.0
            if proc.returncode != 0:
                raise SystemExit(f"{label} failed ({proc.returncode}):\n{proc.stderr}")
            samples.setdefault(label, []).append(elapsed)
            digests[label] = hashlib.sha256(proc.stdout.encode()).hexdigest()[:16]
            found = _WORK_RE.search(proc.stderr)
            if found:
                works.setdefault(label, []).append(float(found.group(1)))
                imp = _IMPORT_RE.search(proc.stderr)
                imports.setdefault(label, []).append(
                    float(imp.group(1)) if imp else 0.0)
        print(f"  round {len(samples['zig ReleaseFast'])}/{args.runs}", end="\r")
    print()
    loadavg.append(os.getloadavg())

    medians = {label: statistics.median(samples[label]) for label, _, _ in SCANNERS}
    mins = {label: min(samples[label]) for label, _, _ in SCANNERS}
    p25 = {label: statistics.quantiles(samples[label], n=4)[0] for label, _, _ in SCANNERS}
    work_medians = {label: (statistics.median(works[label]) if label in works else None)
                    for label, _, _ in SCANNERS}
    import_medians = {label: (statistics.median(imports[label]) if label in imports else None)
                      for label, _, _ in SCANNERS}
    report = {
        "input": str(input_path),
        "bytes": input_path.stat().st_size,
        "sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "runs": args.runs,
        "core": CORE,
        "impls": [label for label, _, _ in SCANNERS],
        "medians_ms": medians,
        "mins_ms": mins,
        "p25_ms": p25,
        "work_medians_ms": work_medians,
        "import_medians_ms": import_medians,
        "samples_ms": samples,
        "work_samples_ms": works,
        "output_digest": digests,
        "reference_digest": reference,
        "loadavg": loadavg,
        "python": str(python),
        "zig_rf_median_ms": medians["zig ReleaseFast"],
        "note": ("asm-* are static syscall-only x86-64 in asm/; qbe-* are "
                 "hand-written QBE IR in qbe/ linked with cc -static; Python "
                 "work_medians_ms excludes the lazy numpy import, which is in "
                 "import_medians_ms."),
    }
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "scan-floor.json").write_text(json.dumps(report, indent=2) + "\n")

    print(f"\nscan floor, {args.runs} rounds (ms); the host is shared, so the "
          f"median is load-contaminated and min is the floor\n")
    print(f"{'implementation':<22}{'min':>9}{'p25':>9}{'median':>9}{'min/zig':>9}{'in-proc':>9}  digest")
    print("-" * 78)
    order = sorted(SCANNERS, key=lambda row: mins[row[0]])
    for label, _, _ in order:
        ratio = mins[label] / mins["zig ReleaseFast"]
        work = work_medians[label]
        marker = digests[label] == reference
        print(f"{label:<22}{mins[label]:>9.3f}{p25[label]:>9.3f}{medians[label]:>9.3f}"
              f"{ratio:>9.2f}x{(f'{work:.3f}' if work is not None else '-'):>9}  "
              f"{'ok' if marker else 'differs'}")
    print(f"\nreference digest {reference} (zig ReleaseFast --scan)")
    print(f"wrote {EVIDENCE / 'scan-floor.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
