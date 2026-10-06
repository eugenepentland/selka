#!/usr/bin/env python3
"""S4 spike 2 and 3: codegen-unit compile cost and edit ripple.

compile N: split syn<N>'s debug and release `.ll` into per-file units, compile each
  unit alone on CPU 10 (fresh zig cache), link, run, and compare the output with the
  whole-program build. Reports the serial sum, the largest unit, and the LPT schedule
  length on 8 and 16 workers, against compiling the single `.ll`.
ripple N K: emit the program with module K edited two ways (a changed constant,
  `--edit`, and an added statement with a new checked operation, `--grow`), and count
  the units whose text changed, raw (today's emitter) and normalized (unit-local
  constant, metadata and trap-site numbering, as S4-1 requires).
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CORE = os.path.join(ROOT, ".mylang-cache/s4/rf/bin/mylang-core")
WORK = os.path.join(ROOT, ".mylang-cache/s4/work")
CPU = ["-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6"]
sys.path.insert(0, HERE)
import split_ll  # noqa: E402


def run(argv, env=None, pin=True):
    start = time.perf_counter()
    result = subprocess.run((["taskset", "-c", "10"] if pin else []) + argv, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-3000:])
        raise SystemExit(f"failed: {' '.join(argv[:6])}")
    return time.perf_counter() - start, result.stdout


def fresh(tag):
    cache = os.path.join(WORK, f"zc-{tag}")
    shutil.rmtree(cache, ignore_errors=True)
    env = dict(os.environ)
    env["ZIG_LOCAL_CACHE_DIR"] = cache
    return env


def lpt(times, workers):
    loads = [0.0] * workers
    for t in sorted(times, reverse=True):
        loads[loads.index(min(loads))] += t
    return max(loads)


def emit(project, release, out_ll):
    cache = os.path.join(WORK, "cache")
    argv = [CORE, "build", os.path.join(project, "main.my"), "-o", out_ll + ".exe", "--cache-dir", cache, "--emit-llvm", out_ll]
    if release:
        argv.append("--release")
    run(argv, pin=False)
    return run([out_ll + ".exe"], pin=False)[1]


def compile_units(modules):
    project = os.path.join(WORK, f"syn{modules}")
    if not os.path.isdir(project):
        subprocess.run([sys.executable, os.path.join(HERE, "gen_program.py"), str(modules), project], check=True)
    runtime = [os.path.join(WORK, "cache", n) for n in os.listdir(os.path.join(WORK, "cache")) if n.startswith("core_rt-") and n.endswith(".o")][0]
    rows = []
    for release, level in ((False, "-O0"), (True, "-O3")):
        ll = os.path.join(WORK, f"units{modules}-{level}.ll")
        expected = emit(project, release, ll)
        whole, _ = run(["zig", "cc", "-c", level, *CPU, "-Wno-override-module", "-o", ll + ".o", ll], fresh("whole"))
        units = split_ll.split(open(ll).read(), False)
        directory = os.path.join(WORK, f"units{modules}{level}")
        shutil.rmtree(directory, ignore_errors=True)
        os.makedirs(directory)
        times = {}
        for name, text in units.items():
            path = os.path.join(directory, f"{name}.ll")
            with open(path, "w") as handle:
                handle.write(text)
            times[name], _ = run(["zig", "cc", "-c", level, *CPU, "-Wno-override-module", "-o", path[:-3] + ".o", path], fresh("u"))
        exe = os.path.join(directory, "split.exe")
        objects = [os.path.join(directory, f"{n}.o") for n in units]
        link, _ = run(["zig", "cc", "-o", exe, *objects, runtime], fresh("link"))
        got = run([exe], pin=False)[1]
        row = {
            "modules": modules, "level": level, "units": len(units), "whole": whole,
            "unit_sum": sum(times.values()), "unit_max": max(times.values()),
            "lpt8": lpt(times.values(), 8), "lpt16": lpt(times.values(), 16),
            "link_units": link, "output_matches": got == expected,
        }
        rows.append(row)
        print(json.dumps({k: round(v, 2) if isinstance(v, float) else v for k, v in row.items()}), flush=True)
    return rows


def unit_hashes(project, release, normalized, tag):
    ll = os.path.join(WORK, f"ripple-{tag}.ll")
    emit(project, release, ll)
    units = split_ll.split(open(ll).read(), normalized)
    return {n: hashlib.sha256(t.encode()).hexdigest() for n, t in units.items()}


def ripple(modules, target, kinds=("edit", "grow", "helper")):
    rows = []
    base = os.path.join(WORK, f"syn{modules}")
    variants = {}
    for kind in kinds:
        path = os.path.join(WORK, f"syn{modules}-{kind}{target}")
        shutil.rmtree(path, ignore_errors=True)
        subprocess.run([sys.executable, os.path.join(HERE, "gen_program.py"), str(modules), path, f"--{kind}", str(target)], check=True)
        variants[kind] = path
    for release in (False, True):
        for normalized in (False, True):
            before = unit_hashes(base, release, normalized, "base")
            for kind, path in variants.items():
                after = unit_hashes(path, release, normalized, kind)
                changed = sorted(n for n in before if before[n] != after.get(n))
                row = {"modules": modules, "edited_module": target, "edit": kind, "release": release,
                       "normalized": normalized, "units": len(before), "changed": len(changed), "which": changed[:8]}
                rows.append(row)
                print(json.dumps(row), flush=True)
    return rows


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "compile":
        rows = [r for n in sys.argv[2:] for r in compile_units(int(n))]
        name = "units-compile.json"
    else:
        rows = ripple(int(sys.argv[2]), int(sys.argv[3])) + ripple(int(sys.argv[2]), int(sys.argv[3]) - 50, ("helper",))
        name = "units-ripple.json"
    with open(os.path.join(HERE, name), "w") as handle:
        json.dump(rows, handle, indent=1)
