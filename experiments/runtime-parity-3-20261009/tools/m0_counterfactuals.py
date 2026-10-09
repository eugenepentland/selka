#!/usr/bin/env python3
"""Build M0 counterfactuals on CPU 8 and retain binaries for quiet CPU-10 confirmation."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]
COMPILER = "/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang"
WORK = ROOT / ".mylang-cache/rp3/counterfactuals-v2"
SLOT = ROOT / "scripts/build-slot.sh"


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    lox = ROOT / ".mylang-cache/lox"
    sizes = json.loads((lox / "bench/sizes.json").read_text())
    scripts = WORK / "scripts"
    scripts.mkdir(exist_ok=True)
    cases = []
    for engine, name in (("vm", "invocation"), ("vm", "fib"), ("vm", "method_call"),
                         ("vm", "string_equality"), ("tree", "equality"), ("tree", "string_equality")):
        original = (lox / "bench/scripts" / (name + ".lox")).read_text()
        first, rest = original.split("\n", 1)
        assert first.startswith("var N = ")
        script = scripts / (engine + "-" + name + ".lox")
        script.write_text("var N = " + str(sizes[name][engine]) + ";\n" + rest)
        cases += ["--case", engine + "/" + name + "=" + json.dumps(["--engine=" + engine, str(script)])]
    command = [sys.executable, str(AREA / "tools/cf_current.py"), "--program", str(lox / "ports/mylang/main.my"),
               "--mylang", COMPILER, "--work", str(WORK), "--name", "lox", "--cwd", str(lox),
               "--variants", "base,norc,checks+norc", "--rounds", "5", "--cpu", "8", "--keep", *cases]
    with (ROOT / ".tmp/rp3/cf-lox.log").open("w") as log:
        subprocess.run([str(SLOT), "build", *command], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    eda = Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
    manifest = json.loads((eda / "golden/manifest.json").read_text())["cases"]
    for name in ("rds3+flat", "labstation"):
        case = next(c for c in manifest if c["id"] == name)
        output = WORK / ("eda-output-" + name)
        args = ["--model", str(eda / "golden/cases" / name / "model.sexp"),
                "--project-dir", str(eda / "golden/projects" / case["project"]),
                "--out-dir", str(output), *case["flags"]]
        command = [sys.executable, str(AREA / "tools/cf_current.py"), "--program", str(ROOT / ".mylang-cache/eda-src/src/main.my"),
                   "--mylang", COMPILER, "--work", str(WORK), "--name", "eda-" + name,
                   "--cwd", str(ROOT / ".mylang-cache/eda-src"), "--variants", "base,norc,checks+norc,reference-inline",
                   "--rounds", "5", "--cpu", "8", "--keep", "--outdir-check", str(output),
                   "--case", name + "=" + json.dumps(args)]
        with (ROOT / ".tmp/rp3" / ("cf-eda-" + name + ".log")).open("w") as log:
            subprocess.run([str(SLOT), "build", *command], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)


if __name__ == "__main__":
    main()
