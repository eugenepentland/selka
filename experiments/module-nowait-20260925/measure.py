#!/usr/bin/env python3
"""Measure `mylang test` right after a cold run, while a detached seeder may
still be compiling (MODULE-TEST-6; docs/audits/devspeed-module-test-2026-09-24.md,
"Update: runs never wait").

usage: measure.py MYLANG TIER_DIR WORK_DIR [--repeats N] [--samples N]
                  [--label L] [--json OUT] [--seeder]

TIER_DIR is a gen_scale.py mylang directory (m000.my ... main.my). Each repeat
copies it to WORK_DIR/test/src with a fresh cache and runs `test main.my
--cache-dir WORK/test/cache` under `taskset -c 0-11` and `/usr/bin/time`:

1. `cold`: the first run;
2. `after_cold`: an unchanged run started the moment the cold run returns;
3. `after_cold_edit`: a body edit (the EDIT_BODY line of the middle module)
   and a run started the moment `after_cold` returns;
4. `seeded_after_s`: with --seeder, the time until the detached seeder is
   done (the test variant's records saved and no path marked as a seeder's);
5. `noop` and `body_edit`: then the steady state, the minimum of --samples
   runs, each edit its own.

Each run records how it was staged (`stage`: `stable`, `private`, or
`seeding` when a seeder held the snapshot path) and how many modules it
compiled, from its MYLANG_TEST_TRACE (a compiler without the `stage` trace
line records null). The scratch root is TMPDIR (the caller sets it). The
1-minute load average is recorded at the start and the end.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def run(cmd, cwd, trace):
    """One run, its wall time, largest process, test counts, and how it was
    staged (`stable`, `private` or `seeding`, from its trace)."""
    trace.unlink(missing_ok=True)
    env = dict(os.environ, MYLANG_TEST_TRACE=str(trace))
    started = time.perf_counter()
    proc = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M", "taskset", "-c", "0-11"] + cmd, cwd=cwd, capture_output=True, text=True, env=env)
    wall = time.perf_counter() - started
    rss = re.search(r"__RSS__ (\d+)", proc.stderr)
    out = {"wall_s": round(wall, 3), "rss_mb": round(int(rss.group(1)) / 1024, 1) if rss else None, "status": proc.returncode}
    counts = re.search(r"(\d+) passed, (\d+) cached, (\d+) failed", proc.stdout)
    if counts:
        out["passed"], out["cached"], out["failed"] = (int(g) for g in counts.groups())
    if proc.returncode != 0:
        out["stderr"] = proc.stderr[-400:]
    lines = trace.read_text().splitlines() if trace.exists() else []
    out["stage"] = next((line.split()[1] for line in lines if line.startswith("stage ")), None)
    out["modules_compiled"] = sum(1 for line in lines if line.startswith("compile-module "))
    return out


def load():
    return float(open("/proc/loadavg").read().split()[0])


def seeding():
    scratch = os.environ.get("TMPDIR") or "/tmp"
    return bool(glob.glob(os.path.join(scratch, ".pending", "snapshot-*", "seeding")))


def seeded(cache):
    return any("standard-" not in path for path in glob.glob(str(cache / "objects" / "*" / "modules" / "*" / "state.json")))


def settle(cache, limit=300.0):
    """Seconds until the seeder's records are saved and it holds no path."""
    started = time.perf_counter()
    while time.perf_counter() - started < limit:
        if seeded(cache) and not seeding():
            return round(time.perf_counter() - started, 3)
        time.sleep(0.05)
    return None


class Tree:
    def __init__(self, tier, work):
        shutil.rmtree(work, ignore_errors=True)
        work.mkdir(parents=True)
        self.work = work
        self.src = work / "src"
        shutil.copytree(tier, self.src)
        modules = sorted(p.stem for p in self.src.glob("m[0-9]*.my"))
        self.middle = self.src / f"{modules[len(modules) // 2]}.my"
        self.edits = 0

    def body_edit(self):
        self.edits += 1
        text = self.middle.read_text()
        new, count = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{9100 + self.edits}{m.group(3)}", text, count=1)
        assert count == 1, "no EDIT_BODY marker"
        self.middle.write_text(new)


def once(tier, work, mylang, samples, seeder):
    tree = Tree(tier, work / "test")
    cache = tree.work / "cache"
    command = [mylang, "test", "main.my", "--cache-dir", str(cache)]
    trace = tree.work / "trace.txt"
    out = {"cold": run(command, tree.src, trace)}
    out["after_cold"] = run(command, tree.src, trace)
    tree.body_edit()
    out["after_cold_edit"] = run(command, tree.src, trace)
    out["seeded_after_s"] = settle(cache) if seeder else None
    out["noop"] = min((run(command, tree.src, trace) for _ in range(samples)), key=lambda s: s["wall_s"])
    edits = []
    for _ in range(samples):
        tree.body_edit()
        edits.append(run(command, tree.src, trace))
    out["body_edit"] = min(edits, key=lambda s: s["wall_s"])
    shutil.rmtree(tree.work, ignore_errors=True)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("tier")
    parser.add_argument("work")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--label", default="")
    parser.add_argument("--json")
    parser.add_argument("--seeder", action="store_true", help="the compiler starts a detached seeder; wait for it before the steady state")
    args = parser.parse_args()
    mylang = str(Path(args.mylang).resolve())
    work = Path(args.work).resolve()
    result = {"label": args.label, "tier": args.tier, "load_start": load(), "repeats": []}
    for _ in range(args.repeats):
        result["repeats"].append(once(args.tier, work, mylang, args.samples, args.seeder))
    result["load_end"] = load()
    text = json.dumps(result, indent=1)
    if args.json:
        Path(args.json).write_text(text)
    print(text)


if __name__ == "__main__":
    main()
