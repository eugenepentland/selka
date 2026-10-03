"""Untimed generic dispatch oracle; invoke through scripts/build-slot.sh."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TEMP = Path(os.environ["TMPDIR"])
COMPILER = ROOT / "zig-out/focus/mylang"
QBE = ROOT / "zig-out/focus/qbe"
CASES = [(kind, count, seed) for kind in (-1, 0, 1, 2, 3, 99)
         for count, seed in ((0, 13), (3, 0))]
CASES += [(0, 4, 0), (1, 3, (1 << 63) - 2),
          (0, 3, (1 << 63) - 2), (3, 3, -(1 << 63))]
GC_CASES = [(0, 3, 0), (99, 3, 0), (0, 0, 13), (0, 3, (1 << 63) - 2)]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


records = []
for mode, name, cases in (("rc", "unswitch-native.my", CASES),
                          ("gc", "unswitch-gc-native.my", GC_CASES)):
    source = HERE / name
    variants = {}
    for backend in ("accounted-qbe", "fast-qbe", "fast-llvm"):
        exe = TEMP / f"unswitch-{mode}-{backend}"
        flags = ["--release"] if backend == "fast-llvm" else ["--qbe", str(QBE)]
        if backend == "accounted-qbe":
            flags += ["--step-accounting"]
        if mode == "gc":
            flags += ["--gc-runtime"]
        command = [str(COMPILER), "build", str(source), *flags,
                   "--keep-symbols", "--timings=json", "-o", str(exe)]
        start = time.monotonic_ns()
        build = subprocess.run(command, check=True, cwd=ROOT, text=True, capture_output=True)
        elapsed = time.monotonic_ns() - start
        phases = []
        for line in build.stderr.splitlines():
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if item.get("version") == "phase-timings-v1":
                phases.append(item)
        variants[backend] = {"command": command, "executable_sha256": digest(exe),
                             "single_build_observation_ns": elapsed, "phases": phases}
    observed = []
    for kind, count, seed in cases:
        outcomes = {}
        for backend in variants:
            exe = TEMP / f"unswitch-{mode}-{backend}"
            environment = os.environ.copy()
            environment["MYLANG_OPTIONS"] = "--print-result"
            run = subprocess.run([str(exe), str(kind), str(count), str(seed)],
                                 text=True, capture_output=True, env=environment)
            outcomes[backend] = {"returncode": run.returncode, "stdout": run.stdout,
                                 "stderr": run.stderr}
        assert outcomes["accounted-qbe"] == outcomes["fast-qbe"], (mode, kind, count, seed, outcomes)
        assert outcomes["accounted-qbe"] == outcomes["fast-llvm"], (mode, kind, count, seed, outcomes)
        observed.append({"arguments": [kind, count, seed], "outcome": outcomes["accounted-qbe"]})
    records.append({"runtime": mode, "source": name, "source_sha256": digest(source),
                    "variants": variants, "cases": observed})
receipt = {"kind": "untimed-accounted-vs-fast-native-dispatch-oracle",
           "compiler_mode": "Debug compiler, ReleaseFast guests",
           "compiler_sha256": digest(COMPILER), "qbe_sha256": digest(QBE),
           "zig_version": subprocess.check_output(["zig", "version"], text=True).strip(),
           "compile_cost": "Each duration is a single build observation under build-slot affinity; cache state and concurrent load are uncontrolled. No statistical comparison.",
           "records": records}
(HERE / "p2-unswitch-boundaries.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(f"{sum(len(r['cases']) for r in records)} exact accounted-QBE/fast-QBE/fast-LLVM outcomes matched")
