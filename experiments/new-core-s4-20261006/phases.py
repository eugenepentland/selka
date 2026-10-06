#!/usr/bin/env python3
"""S4 spike 1: phase costs of the new core at scale, pinned to CPU 10.

For each size, generate the synthetic program and time:
  check     `mylang-core dump-typed FILE <no such function>` (load + check, no output)
  debug     `mylang-core build` debug, with LLVM time subtracted (IR, ownership, emission)
  release   `mylang-core build --release`, LLVM subtracted (IR, release passes, emission)
  llvm_O0   `zig cc -c -O0` on the emitted debug .ll, fresh zig cache
  llvm_O3   `zig cc -c -O3` on the emitted release .ll, fresh zig cache
  link      `zig cc` linking the program object with the runtime object
Every zig cc run gets a fresh ZIG_LOCAL_CACHE_DIR, so no program object is reused;
the global cache (libc, compiler-rt) stays warm, as on a developer machine.
"""
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
PIN = ["taskset", "-c", "10"]


def timed(argv, env=None):
    start = time.perf_counter()
    result = subprocess.run(PIN + argv, capture_output=True, text=True, env=env)
    elapsed = time.perf_counter() - start
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-4000:])
        raise SystemExit(f"failed: {' '.join(argv)}")
    return elapsed


def fresh_env(tag):
    cache = os.path.join(WORK, f"zig-cache-{tag}")
    shutil.rmtree(cache, ignore_errors=True)
    env = dict(os.environ)
    env["ZIG_LOCAL_CACHE_DIR"] = cache
    return env


def runtime_object():
    """The core's cached runtime object, built by a first warm-up build."""
    objects = [n for n in os.listdir(os.path.join(WORK, "cache")) if n.startswith("core_rt-") and n.endswith(".o")]
    return os.path.join(WORK, "cache", objects[0])


def measure(modules):
    project = os.path.join(WORK, f"syn{modules}")
    shutil.rmtree(project, ignore_errors=True)
    subprocess.run([sys.executable, os.path.join(HERE, "gen_program.py"), str(modules), project], check=True)
    source = os.path.join(project, "main.my")
    lines = sum(sum(1 for _ in open(os.path.join(project, n))) for n in os.listdir(project))
    cache = os.path.join(WORK, "cache")
    debug_ll = os.path.join(WORK, f"syn{modules}-debug.ll")
    release_ll = os.path.join(WORK, f"syn{modules}-release.ll")
    row = {"modules": modules, "files": len(os.listdir(project)), "lines": lines}
    row["check"] = timed([CORE, "dump-typed", source, "no_such_function"])
    # The driver points zig's local cache at <cache>/zig-local, which would reuse the
    # previous run's object for identical text; clear it so every build is cold.
    shutil.rmtree(os.path.join(cache, "zig-local"), ignore_errors=True)
    total_debug = timed([CORE, "build", source, "-o", os.path.join(WORK, "out-debug"), "--cache-dir", cache, "--emit-llvm", debug_ll], fresh_env("d"))
    shutil.rmtree(os.path.join(cache, "zig-local"), ignore_errors=True)
    total_release = timed([CORE, "build", source, "-o", os.path.join(WORK, "out-release"), "--release", "--cache-dir", cache, "--emit-llvm", release_ll], fresh_env("r"))
    obj_d = os.path.join(WORK, "prog-d.o")
    obj_r = os.path.join(WORK, "prog-r.o")
    row["llvm_O0"] = timed(["zig", "cc", "-c", "-O0", *CPU, "-Wno-override-module", "-o", obj_d, debug_ll], fresh_env("c0"))
    row["llvm_O3"] = timed(["zig", "cc", "-c", "-O3", *CPU, "-Wno-override-module", "-o", obj_r, release_ll], fresh_env("c3"))
    row["link"] = timed(["zig", "cc", "-O0", "-o", os.path.join(WORK, "linked"), obj_d, runtime_object()], fresh_env("l"))
    # The builds compile and link in one zig cc call; subtract that to leave the core's own work.
    row["core_debug"] = total_debug - row["llvm_O0"] - row["link"]
    row["core_release"] = total_release - row["llvm_O3"] - row["link"]
    row["total_debug"] = total_debug
    row["total_release"] = total_release
    row["ll_bytes_debug"] = os.path.getsize(debug_ll)
    row["ll_bytes_release"] = os.path.getsize(release_ll)
    return row


if __name__ == "__main__":
    sizes = [int(s) for s in sys.argv[1:]] or [120, 1200]
    os.makedirs(WORK, exist_ok=True)
    rows = []
    for modules in sizes:
        row = measure(modules)
        rows.append(row)
        print(json.dumps({k: round(v, 2) if isinstance(v, float) else v for k, v in row.items()}), flush=True)
    with open(os.path.join(HERE, "phases.json"), "w") as handle:
        json.dump(rows, handle, indent=1)
