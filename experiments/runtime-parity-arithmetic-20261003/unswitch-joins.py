"""Untimed admitted producer-join matrix; invoke through build-slot.sh."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess

FORMS = (
    "kind == 2 or kind == 3",
    "kind == 2 and kind != 3",
    "(kind == 2 or kind == 3) and i < seed",
    "i < seed and (kind == 2 or kind == 3)",
    "(kind == 2 if i < seed else kind == 3)",
    "kind == 2 or 1 // (seed - i) > 0",
    "(seed if i < 1 else kind) == 2",
    "i < seed or kind == 2",
)
parser = argparse.ArgumentParser()
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--qbe", type=Path, required=True)
parser.add_argument("--compiler-revision", required=True)
parser.add_argument("--host-mode", choices=("Debug", "ReleaseFast"), required=True)
parser.add_argument("--output", type=Path, required=True)
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
source = Path(__file__).with_suffix(".my")
template = source.read_text()
needle = "        if kind == 2 or kind == 3:\n"
assert template.count(needle) == 1
environment = dict(os.environ)
environment.pop("MYLANG_MEMORY_LIMIT", None)
environment["MYLANG_OPTIONS"] = "--print-result"


def artifact(path):
    path = Path(path)
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def logged(command, name):
    result = subprocess.run(command, capture_output=True)
    stdout = options.output / f"{name}.stdout.log"
    stderr = options.output / f"{name}.stderr.log"
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    result.check_returncode()
    return result, {"command": command, "exit": result.returncode,
                    "stdout": artifact(stdout), "stderr": artifact(stderr)}


def oracle(form, kind, count, seed):
    output = []
    total = 0
    for index in range(count):
        total += int(kind == 2)
        output.append(f"{index}\n")
        try:
            condition = (
                lambda: kind == 2 or kind == 3,
                lambda: kind == 2 and kind != 3,
                lambda: (kind == 2 or kind == 3) and index < seed,
                lambda: index < seed and (kind == 2 or kind == 3),
                lambda: kind == 2 if index < seed else kind == 3,
                lambda: kind == 2 or 1 // (seed - index) > 0,
                lambda: (seed if index < 1 else kind) == 2,
                lambda: index < seed or kind == 2,
            )[form]()
        except ZeroDivisionError:
            return 1, "".join(output).encode(), b"R_DIVISION_BY_ZERO"
        total += 3 if condition else 7
    output.extend((f"{total}\n", f"{total}\n"))
    return total, "".join(output).encode(), b""


records = []
for form, condition in enumerate(FORMS):
    derived = options.output / f"form-{form}.my"
    derived.write_text(template.replace(needle, f"        if {condition}:\n"))
    emitted, emission = logged([str(options.compiler), "emit-qbe", str(derived),
                               "--drop-step-checks", "--drop-frame-checks"], f"form-{form}-emission")
    manifest = json.loads(emitted.stdout)
    main = next(function for function in manifest["functions"] if function["name"] == "main")
    assert "QBE-LOOP-UNSWITCH-1" in main["il"], (form, "loop was not admitted")
    variants = {}
    for lane, backend in (("accounted-qbe", "qbe"), ("fast-qbe", "qbe"), ("fast-llvm", "llvm")):
        executable = options.output / f"form-{form}-{lane}"
        flags = ["--release"] if backend == "llvm" else ["--qbe", str(options.qbe), "--backend", "qbe", "--mode", "ReleaseFast"]
        if lane == "accounted-qbe":
            flags += ["--step-accounting"]
        _, build = logged([str(options.compiler), "build", str(derived), *flags, "--keep-symbols",
                           f"--cache-dir={options.output / ('cache-' + lane)}", "-o", str(executable)],
                          f"form-{form}-{lane}-build")
        native_manifest = Path(f"{executable}.qbe-manifest.json")
        effective = json.loads(native_manifest.read_text())
        assert effective["backend"] == backend, (lane, effective["backend"])
        if backend == "llvm":
            assert effective["optimization"] == "3" and effective["lto"]
        probe = subprocess.run([str(executable), "2", "3", "1"], capture_output=True,
                               env={**environment, "MYLANG_OPTIONS": "--max-steps=1"})
        expected = b"R_STEP_LIMIT" if lane == "accounted-qbe" else b"R_NO_STEP_ACCOUNTING"
        assert expected in probe.stderr, (lane, probe.stderr)
        variants[lane] = {"backend": backend, "guest_mode": "ReleaseFast", "build": build,
                          "executable": artifact(executable), "manifest": artifact(native_manifest),
                          "mode_probe": expected.decode()}
    cases = []
    for kind, count, seed in itertools.product((2, 3, 99), (0, 3), (0, 1, 2)):
        arguments = [str(kind), str(count), str(seed)]
        outcomes = {}
        for lane, variant in variants.items():
            result = subprocess.run([variant["executable"]["path"], *arguments], capture_output=True, env=environment)
            outcomes[lane] = (result.returncode, result.stdout, result.stderr)
        baseline = outcomes["accounted-qbe"]
        assert all(result == baseline for result in outcomes.values()), (form, arguments, outcomes)
        expected = oracle(form, kind, count, seed)
        assert baseline[:2] == expected[:2], (form, arguments, baseline, expected)
        assert (expected[2] in baseline[2]) if expected[2] else not baseline[2], (form, arguments, baseline)
        cases.append({"arguments": arguments, "returncode": baseline[0], "stdout": baseline[1].decode(),
                      "stderr": baseline[2].decode(), "oracle_trap": expected[2].decode()})
    records.append({"form": form, "condition": condition, "source": artifact(derived), "admitted": True,
                    "emission": emission, "variants": variants, "cases": cases})
    print(f"form {form}: admitted; {len(cases)} exact three-lane outcomes and independent oracle matched", flush=True)

receipt = {"kind": "untimed-admitted-short-circuit-join-matrix", "compiler_revision": options.compiler_revision,
           "host_mode": options.host_mode, "compiler": artifact(options.compiler), "qbe": artifact(options.qbe),
           "template": artifact(source), "runner": artifact(Path(__file__)),
           "guest_mode": "ReleaseFast", "cases": sum(len(record["cases"]) for record in records),
           "guest_executions": sum(len(record["cases"]) * 3 for record in records), "records": records}
(options.output / "unswitch-joins.json").write_text(json.dumps(receipt, indent=2) + "\n")
