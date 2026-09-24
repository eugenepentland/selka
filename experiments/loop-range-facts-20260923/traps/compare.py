#!/usr/bin/env python3
"""Build every trap program with two compilers in several modes and require
byte-identical stdout, stderr and exit status between them.

usage: compare.py BASE_MYLANG LANE_MYLANG WORK [PROGRAM.my...]
Modes: the release default (LLVM, full LTO), QBE (`--backend qbe`), and the
release default run under `MYLANG_OPTIONS=--gc-stress`. A step-accounted run
(`mylang run --max-steps`) versions nothing and is covered by the Zig tests.
"""
import glob
import os
import subprocess
import sys

base, lane, work, *programs = sys.argv[1:]
here = os.path.dirname(os.path.abspath(__file__))
programs = programs or sorted(glob.glob(os.path.join(here, "*.my")))
os.makedirs(work, exist_ok=True)
env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
MODES = {"llvm": [], "qbe": ["--backend", "qbe"]}


def build(compiler, source, output, flags):
    r = subprocess.run([compiler, "build", source, "-o", output, f"--cache-dir={work}/cache", *flags],
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise SystemExit(f"build failed: {compiler} {source}\n{r.stderr}")


def run(binary, stress):
    run_env = dict(env, MYLANG_OPTIONS="--gc-stress") if stress else env
    r = subprocess.run([binary], capture_output=True, text=True, env=run_env, timeout=120)
    return r.returncode, r.stdout, r.stderr.replace(binary, "PROGRAM")


same = differ = 0
for source in programs:
    name = os.path.splitext(os.path.basename(source))[0]
    for mode, flags in MODES.items():
        outputs = {}
        for label, compiler in (("base", base), ("lane", lane)):
            binary = os.path.join(work, f"{name}.{mode}.{label}")
            build(compiler, source, binary, flags)
            outputs[label] = [run(binary, False)] + ([run(binary, True)] if mode == "llvm" else [])
            outputs[label] = [(s, o, e.replace(binary, "PROGRAM")) for s, o, e in outputs[label]]
        for index, (a, b) in enumerate(zip(outputs["base"], outputs["lane"])):
            variant = mode + ("+gc-stress" if index else "")
            if a == b:
                same += 1
                errors = [line for line in a[2].splitlines() if "error[" in line]
                first = errors[0].split("error", 1)[1] if errors else "(no trap)"
                print(f"same   {name:28} {variant:15} status {a[0]}  {first[:110]}")
            else:
                differ += 1
                print(f"DIFFER {name:28} {variant:15}\n  base {a!r}\n  lane {b!r}")
print(f"{same} identical, {differ} different")
sys.exit(1 if differ else 0)
