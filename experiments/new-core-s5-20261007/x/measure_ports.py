#!/usr/bin/env python3
"""S5-X (copied from S4-P): the Lox port and the EDA slice under `mylang`, measured with the
old-core baselines' protocols (Wave 0):

- Lox (codex/s4-lox-value-semantics experiments/new-core-s4-lox-20261006/baselines.json):
  CPU 10, fresh caches including Zig's global cache and the runtime; build, directory
  tests (--jobs 1) and driver-case tests, each cold, unchanged and after the natives.my
  one-function edit.
- EDA (eda-bench codex/s4-eda-stage1 experiments/new-core-s4-eda-20261006/old_core_baselines.py):
  CPU 10, --jobs 1; build and tests, cold, unchanged and after the main.parse_args edit;
  Zig's global cache stays warm ("toolchain-level"); the new core's per-user store is
  private and warmed with the runtime objects only, so unit objects start cold.

Each port is copied to a private directory first; the originals are never edited.
Run under `flock /run/user/1000/mylang-slots/cpu10.lock`.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

LOX = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-s4-lox-value-semantics/benchmarks/lox/ports/mylang")
EDA = Path("/home/epentland/ai/canopy/mylang-worktrees/../eda-bench-wt/claude-s4-eda-newcore/mylang").resolve()
LOX_EDIT = ("natives.my",
            "                    return value.Value.number(float(instant.unix_nanoseconds) / 1000000000.0)\n",
            "                    seconds = float(instant.unix_nanoseconds) / 1000000000.0\n                    return value.Value.number(seconds)\n")
EDA_EDIT = ("src/main.my", "    a = Args()\n", "    initial_args = Args()\n    a = initial_args\n")
BASELINES = {
    "lox": {"build": (7.65688649402, 0.006813724059611559, 0.19524815189652145),
            "tests-directory": (17.077737142099068, 0.11094480706378818, 0.6081309821456671),
            "tests-driver": (4.9182498920708895, 0.034172628074884415, 0.03993511409498751)},
    "eda": {"build": (81.1429, 0.0165, 1.1516), "test": (234.5436, 1.6549, 1.6658)},
}


def run(command, cwd, env, log):
    started = time.perf_counter()
    done = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    seconds = time.perf_counter() - started
    log.append({"argv": command, "seconds": seconds, "status": done.returncode, "tail": (done.stdout + done.stderr)[-600:]})
    if done.returncode != 0:
        raise SystemExit(f"command failed ({done.returncode}): {command}\n{done.stdout[-2000:]}{done.stderr[-2000:]}")
    return seconds


def edit(path, find, replace):
    text = path.read_text()
    if text.count(find) != 1:
        raise SystemExit(f"edit anchor not unique in {path}")
    path.write_text(text.replace(find, replace))


def lox(core, area, log):
    port = area / "lox-port"
    shutil.copytree(LOX, port)
    cache = area / "lox-cache"
    env = {**os.environ, "XDG_CACHE_HOME": str(cache / "xdg"), "ZIG_GLOBAL_CACHE_DIR": str(cache / "zig-global"),
           "ZIG_LOCAL_CACHE_DIR": str(cache / "zig-local"), "TMPDIR": str(cache / "tmp")}
    for key in ("MYLANG_CORE_RUNTIME_CACHE",):
        env.pop(key, None)
    (cache / "tmp").mkdir(parents=True)
    (cache / "out").mkdir()
    commands = {
        "build": [str(core), "build", "main.my", "-o", str(cache / "out/lox"), "--cache-dir", str(cache / "build")],
        "tests-directory": [str(core), "test", ".", "--max-steps=100000000", "--jobs", "1", "--cache-dir", str(cache / "tests")],
        "tests-driver": [str(core), "test", "driver_tests.my", "--cases", "driver_cases.json", "--max-steps=100000000",
                         "--jobs", "1", "--cache-dir", str(cache / "tests")],
    }
    result = {}
    for state in ("cold", "unchanged", "one-function-edit"):
        if state == "one-function-edit":
            edit(port / LOX_EDIT[0], LOX_EDIT[1], LOX_EDIT[2])
        for kind, command in commands.items():
            result.setdefault(kind, {})[state] = run(command, port, env, log)
    return result


def eda(core, area, log, warm_runtime):
    port = area / "eda-port"
    shutil.copytree(EDA, port)
    cache = area / "eda-cache"
    store = cache / "xdg"
    if warm_runtime:
        objects = store / "mylang/core-runtime"
        objects.mkdir(parents=True)
        for item in warm_runtime.iterdir():
            if item.is_file() and (item.name.startswith("core_rt-") or item.name.startswith("core_number_text-")):
                shutil.copy2(item, objects / item.name)
            elif item.is_dir() and item.name.startswith("number-tool-"):
                shutil.copytree(item, objects / item.name)
    env = {**os.environ, "XDG_CACHE_HOME": str(store), "TMPDIR": str(cache / "tmp")}
    env.pop("MYLANG_CORE_RUNTIME_CACHE", None)
    (cache / "tmp").mkdir(parents=True)
    (cache / "bin").mkdir()
    commands = {
        "build": [str(core), "build", "src/main.my", "-o", str(cache / "bin/eda-sch"), "--cache-dir", str(cache / "build")],
        "test": [str(core), "test", "src", "--jobs", "1", "--cache-dir", str(cache / "tests"), "--max-frames", "30000",
                 "--max-steps", "4000000000", "--max-memory", "2G"],
    }
    result = {}
    for kind, command in commands.items():
        result[kind] = {}
        result[kind]["cold"] = run(command, port, env, log)
        result[kind]["unchanged"] = run(command, port, env, log)
        source = port / EDA_EDIT[0]
        original = source.read_text()
        edit(source, EDA_EDIT[1], EDA_EDIT[2])
        result[kind]["one-function-edit"] = run(command, port, env, log)
        source.write_text(original)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--area", type=Path, required=True, help="fresh scratch directory on disk")
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, help="a store directory holding warm core runtime objects for EDA")
    args = parser.parse_args()
    if args.area.exists():
        raise SystemExit("--area must not exist")
    args.area.mkdir(parents=True)
    os.sched_setaffinity(0, {10})
    log = []
    report = {"cpu": 10, "core": str(args.core), "lox": lox(args.core, args.area, log),
              "eda": eda(args.core, args.area, log, args.runtime), "baselines": BASELINES, "commands": log}
    for port in ("lox", "eda"):
        for kind, states in report[port].items():
            base = BASELINES[port][kind]
            report[port][kind]["ratio_to_old"] = {s: states[s] / b for s, b in zip(("cold", "unchanged", "one-function-edit"), base)}
    args.json.write_text(json.dumps(report, indent=1) + "\n")
    for port in ("lox", "eda"):
        for kind, states in report[port].items():
            print(port, kind, {s: round(v, 4) for s, v in states.items() if s != "ratio_to_old"},
                  {s: round(v, 3) for s, v in states["ratio_to_old"].items()})


if __name__ == "__main__":
    main()
