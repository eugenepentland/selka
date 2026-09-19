#!/usr/bin/env python3
"""Runtime comparison: Zig RF/RS, mylang RF, Go, and three Python ports.

Measures the same six phases on all seven implementations over one input, in
interleaved rounds pinned to a single core, then draws a linear-axis chart.

  loop     empty while over the input length       zig-bench --loop
  scan     one bounds-checked byte compare         zig-bench --scan
  tokens   read + tokenize                         zig-bench --tokens
  parse    read + tokenize + parse                 zig-bench --parse
  census   parse + walk the tree                   zig-bench (default)
  render   parse + render                          zig-bench --render

The three compiled columns are the prior benchmark's: Zig ReleaseFast and
ReleaseSafe (`experiments/sexpr-port/zig-bench`), and mylang built with
`mylang build --mode ReleaseFast`, the fastest configuration mylang has (there
is no ReleaseSafe guest mode, and a ReleaseFast executable carries no
instruction-budget accounting).

The two Python columns are `python/sexpr_pure.py` (stdlib only, hand-rolled
byte tokenizer) and `python/sexpr_np.py` (numpy for `--scan`, `re` for token
scanning, same shared parser/census/printer). A third, `python/sexpr_tuned.py`,
keeps that structure but replaces the tokenizer with an unrolled-string
`finditer` one. All three print the same stdout line as `zig-bench`.

The `go` column is `go/main.go`, a straight port with the same six workloads and
the same stdout lines.

Everything lives under a gitignored workspace scratch directory (default
`.tmp/sexpr-implcmp`), because the sandbox makes `/tmp` private to a single
process invocation.

Usage:
  python3 experiments/sexpr-audit/compare_impls.py [--runs N] [--input FILE]
Writes evidence/runtime-compare.json; `runtime_charts.py` draws the figure.
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

AUDIT = Path(__file__).resolve().parent
REPO = AUDIT.parents[1]
PORT = REPO / "experiments/sexpr-port"
PYDIR = AUDIT / "python"
MYLANG = REPO / "zig-out/bin/mylang"
ZIG_BENCH = PORT / "zig-bench"
EDA = Path("/home/epentland/ai/canopy/eda")
FIXTURE = EDA / "projects/designs/lib/modules/poe-pd-flyback-tps23757.sexp"
EVIDENCE = AUDIT / "evidence"
WORK = REPO / ".tmp/sexpr-implcmp"
TASKSET = shutil.which("taskset") or "taskset"
CORE = "6"

IMPLS = [
    "zig ReleaseFast",
    "zig ReleaseSafe",
    "mylang ReleaseFast",
    "go",
    "python pure",
    "python + libs",
    "python tuned",
]
ZIG_OUT = {
    "zig ReleaseFast": WORK / "zb-ReleaseFast-out/bin/zig-bench",
    "zig ReleaseSafe": WORK / "zb-ReleaseSafe-out/bin/zig-bench",
}
GO_DIR = AUDIT / "go"
GO_OUT = WORK / "go-sexpr"
GO = shutil.which("go") or "go"
# phase -> (mylang source, mylang extra args, zig mode argument)
PHASES = {
    "loop": (AUDIT / "h_loop.my", [], "--loop"),
    "scan": (AUDIT / "e_scan.my", [], "--scan"),
    "tokens": (AUDIT / "b_tokens.my", [], "--tokens"),
    "parse": (AUDIT / "c_parse.my", [], "--parse"),
    "census": (PORT / "main.my", [], None),
    "render": (PORT / "main.my", ["--render"], "--render"),
}

_WORK_RE = re.compile(r"work_ms=([0-9.]+)")
_IMPORT_RE = re.compile(r"import_ms=([0-9.]+)")


def ensure_input(target_bytes: int = 1 << 20) -> Path:
    """The deterministic ~1 MiB input: the real 185 kB EDA module repeated."""
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / "input.sexp"
    source = FIXTURE.read_bytes()
    reps = max(1, target_bytes // len(source))
    want = reps * (len(source) + 1)
    if not out.exists() or out.stat().st_size != want:
        with out.open("wb") as handle:
            for _ in range(reps):
                handle.write(source)
                handle.write(b"\n")
    return out


def find_python() -> Path:
    """A CPython with numpy importable, for both Python columns."""
    candidates = [
        Path(os.environ["SEXPR_PYTHON"]) if os.environ.get("SEXPR_PYTHON") else None,
        Path("/home/epentland/ai/canopy/rust-workflow/.venv/bin/python"),
        Path(sys.executable),
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            probe = subprocess.run([str(candidate), "-c", "import numpy"],
                                   capture_output=True)
            if probe.returncode == 0:
                return candidate
    raise SystemExit("no python with numpy found; set SEXPR_PYTHON")


def tool_env() -> dict:
    """Environment for the build tools.

    The sandbox exposes `$HOME` read-only, so the toolchain caches must be
    redirected under the (writable) workspace scratch directory.
    """
    return dict(os.environ,
                ZIG_LOCAL_CACHE_DIR=str(WORK / "zig-local"),
                ZIG_GLOBAL_CACHE_DIR=str(WORK / "zig-global"))


def build_zig(force: bool) -> None:
    targets = {
        "ReleaseFast": WORK / "zb-ReleaseFast-out",
        "ReleaseSafe": WORK / "zb-ReleaseSafe-out",
    }
    if not force and all((prefix / "bin/zig-bench").exists() for prefix in targets.values()):
        return
    env = tool_env()
    for mode, prefix in targets.items():
        proc = subprocess.run(
            ["zig", "build", f"-Doptimize={mode}", "-p", str(prefix)],
            cwd=ZIG_BENCH, capture_output=True, text=True, env=env)
        if proc.returncode != 0:
            raise SystemExit(f"zig build {mode} failed:\n{proc.stdout}\n{proc.stderr}")
        print(f"  built zig {mode}")


def build_mylang(force: bool) -> dict:
    built = {}
    env = tool_env()
    cache = WORK / "my-cache"
    for phase, (source, _, _) in PHASES.items():
        binary = WORK / f"my-{phase}"
        if force or not binary.exists() or binary.stat().st_mtime < MYLANG.stat().st_mtime:
            proc = subprocess.run(
                [str(MYLANG), "build", str(source.relative_to(REPO)), "-o", str(binary),
                 "--mode", "ReleaseFast", f"--cache-dir={cache}"],
                cwd=REPO, capture_output=True, text=True, env=env)
            if proc.returncode != 0:
                raise SystemExit(f"building {phase} failed:\n{proc.stdout}\n{proc.stderr}")
            print(f"  built mylang {phase}")
        built[phase] = binary
    return built


def build_go(force: bool) -> None:
    """Build the Go driver with its caches under the workspace scratch dir."""
    source = GO_DIR / "main.go"
    if not force and GO_OUT.exists() and GO_OUT.stat().st_mtime >= source.stat().st_mtime:
        return
    env = dict(tool_env(),
               GOCACHE=str(WORK / "gocache"),
               GOPATH=str(WORK / "gopath"),
               GOFLAGS="-mod=mod")
    proc = subprocess.run(
        [GO, "build", "-C", str(GO_DIR), "-o", str(GO_OUT), "."],
        capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise SystemExit(f"go build failed:\n{proc.stdout}\n{proc.stderr}")
    print("  built go")


def argv_for(impl: str, phase: str, input_path: Path, mylang_binaries: dict,
             python: Path) -> list:
    _, my_args, zig_mode = PHASES[phase]
    if impl == "mylang ReleaseFast":
        return [str(mylang_binaries[phase]), str(input_path), *my_args]
    if impl == "go":
        return [str(GO_OUT), str(input_path), *([zig_mode] if zig_mode else [])]
    if impl.startswith("zig "):
        return [str(ZIG_OUT[impl]), str(input_path), *([zig_mode] if zig_mode else [])]
    scripts = {
        "python pure": "sexpr_pure.py",
        "python + libs": "sexpr_np.py",
        "python tuned": "sexpr_tuned.py",
    }
    script = PYDIR / scripts[impl]
    return [str(python), str(script), str(input_path), *([zig_mode] if zig_mode else [])]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=31)
    ap.add_argument("--input", default=None)
    ap.add_argument("--rebuild", action="store_true",
                    help="rebuild the Zig drivers and every mylang phase binary")
    args = ap.parse_args()

    input_path = Path(args.input) if args.input else ensure_input()
    if not input_path.exists():
        raise SystemExit(f"missing input {input_path}")

    python = find_python()
    print(f"input {input_path} ({input_path.stat().st_size} bytes)")
    print(f"python {python}")
    print("building ...")
    build_zig(args.rebuild)
    mylang_binaries = build_mylang(args.rebuild)
    build_go(args.rebuild)

    for impl, path in ZIG_OUT.items():
        if not path.exists():
            raise SystemExit(f"missing {impl} driver at {path}")

    samples: dict = {impl: {} for impl in IMPLS}
    works: dict = {impl: {} for impl in IMPLS}
    imports: dict = {impl: {} for impl in IMPLS}
    digests: dict = {impl: {} for impl in IMPLS}
    loadavg = [os.getloadavg()]
    # One interleaved batch: every round runs every implementation before the
    # next round, so slow drift in machine load hits all seven equally.
    for phase in PHASES:
        for run in range(args.runs):
            for impl in IMPLS:
                argv = [TASKSET, "-c", CORE,
                        *argv_for(impl, phase, input_path, mylang_binaries, python)]
                start = time.perf_counter()
                proc = subprocess.run(argv, capture_output=True, text=True)
                elapsed = (time.perf_counter() - start) * 1000.0
                if proc.returncode != 0:
                    raise SystemExit(f"{impl} {phase} failed ({proc.returncode}):\n{proc.stderr}")
                samples[impl].setdefault(phase, []).append(elapsed)
                digests[impl][phase] = hashlib.sha256(proc.stdout.encode()).hexdigest()[:16]
                found = _WORK_RE.search(proc.stderr)
                if found:
                    works[impl].setdefault(phase, []).append(float(found.group(1)))
                    imp = _IMPORT_RE.search(proc.stderr)
                    imports[impl].setdefault(phase, []).append(
                        float(imp.group(1)) if imp else 0.0)
        print(f"  {phase} done ({args.runs} rounds)")

    loadavg.append(os.getloadavg())
    medians = {impl: {p: statistics.median(samples[impl][p]) for p in PHASES} for impl in IMPLS}
    work_medians = {impl: {p: statistics.median(works[impl][p]) if works[impl].get(p) else None
                           for p in PHASES} for impl in IMPLS}
    import_medians = {impl: {p: statistics.median(imports[impl][p]) if imports[impl].get(p) else None
                             for p in PHASES} for impl in IMPLS}

    report = {
        "input": str(input_path),
        "bytes": input_path.stat().st_size,
        "sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "runs": args.runs,
        "core": CORE,
        "impls": IMPLS,
        "phases": list(PHASES),
        "medians_ms": medians,
        "work_medians_ms": work_medians,
        "import_medians_ms": import_medians,
        "samples_ms": samples,
        "work_samples_ms": works,
        "output_digest": digests,
        "loadavg": loadavg,
        "python": str(python),
        "note": ("mylang has no ReleaseSafe guest mode; its column is a ReleaseFast "
                 "executable build. The three Python columns run under the same CPython; "
                 "work_medians_ms excludes interpreter start-up and, for the numpy scan, "
                 "the library import. The go and python tuned columns were added after "
                 "the first five-way run."),
    }
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "runtime-compare.json").write_text(json.dumps(report, indent=2) + "\n")

    header = f"{'phase':<9}" + "".join(f"{impl:>19}" for impl in IMPLS)
    print(f"\nprocess wall clock, median of {args.runs} (ms)\n")
    print(header)
    print("-" * len(header))
    for phase in PHASES:
        print(f"{phase:<9}" + "".join(f"{medians[impl][phase]:>19.3f}" for impl in IMPLS))
    print("\nin-process work, median (ms); '- = compiled, startup is sub-ms'\n")
    print(header)
    print("-" * len(header))
    for phase in PHASES:
        row = f"{phase:<9}"
        for impl in IMPLS:
            value = work_medians[impl][phase]
            row += f"{value:>19.3f}" if value is not None else f"{'-':>19}"
        print(row)
    print()
    for phase in PHASES:
        unique = {digests[impl][phase] for impl in IMPLS}
        if len(unique) == 1:
            print(f"  output {phase:<8} identical across all seven")
        else:
            print(f"  output {phase:<8} differs: " +
                  " ".join(f"{i}={digests[i][phase]}" for i in IMPLS))
    print(f"\nwrote {EVIDENCE / 'runtime-compare.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
