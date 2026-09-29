#!/usr/bin/env python3
"""Measure `mylang check`, `mylang test` and `mylang build` on a generated
ladder tier, for stage 1d (docs/audits/devspeed-module-test-2026-09-24.md).

usage: measure.py MYLANG TIER_DIR WORK_DIR [--samples N] [--label L] [--json OUT]
                  [--steps check,test,build]

TIER_DIR is a gen_scale.py mylang directory (m000.my ... main.my). Each step
copies it to WORK_DIR/<step>/src and runs, under `taskset -c $MYLANG_MEASURE_CPUS (default 2,3,10,11)` and
`/usr/bin/time` (whose %M is the largest single process of the tree):

- check: `check main.my --cache-dir=WORK/check/cache`: cold; then, when the
  cold check left a detached seeder building module records (MODULE-CHECK-2),
  the time until its records appear (`seeded_after_s`); then no-op, a body
  edit (a new constant in the EDIT_BODY line of the middle module) and an
  interface edit (a new public function appended to it);
- test: `test main.my --cache-dir WORK/test/cache`: cold; then a rerun
  started at once (`after_cold`), which waits for a detached seeder the cold
  run left (MODULE-TEST-5); then no-op and a body edit, with the executed and
  cached test counts;
- build: `build main.my --project -o ...`: cold, no-op and a body edit.

Each no-op and edit figure is the minimum over the samples, each sample its
own edit. The 1-minute load average is recorded at the start and the end.
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


def run(cmd, cwd):
    started = time.perf_counter()
    proc = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M", "taskset", "-c", os.environ.get("MYLANG_MEASURE_CPUS", "2,3,10,11")] + cmd, cwd=cwd, capture_output=True, text=True)
    wall = time.perf_counter() - started
    rss = re.search(r"__RSS__ (\d+)", proc.stderr)
    out = {"wall_s": round(wall, 3), "rss_mb": round(int(rss.group(1)) / 1024, 1) if rss else None, "status": proc.returncode}
    counts = re.search(r"(\d+) passed, (\d+) cached, (\d+) failed", proc.stdout)
    if counts:
        out["passed"], out["cached"], out["failed"] = (int(g) for g in counts.groups())
    if proc.returncode != 0:
        raise RuntimeError(f"measurement command failed ({proc.returncode}): {cmd!r}\n{proc.stdout}\n{proc.stderr}")
    if cmd[1] == "test":
        expected = int(os.environ["MYLANG_MEASURE_TESTS"])
        if not counts or out["failed"] != 0 or out["passed"] + out["cached"] != expected:
            raise RuntimeError(f"incomplete test measurement: expected {expected}, got {out!r}\n{proc.stdout}")
    return out


def load():
    return float(open("/proc/loadavg").read().split()[0])


def best(samples):
    return min(samples, key=lambda s: s["wall_s"])


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

    def interface_edit(self):
        self.edits += 1
        with self.middle.open("a") as out:
            out.write(f"\n\npublic def zz_added_{self.edits}(n: int) -> int:\n    return n + {self.edits}\n")


def settle(cache, limit=120.0):
    """Seconds until a module variant's records appear under `cache`, or None."""
    started = time.perf_counter()
    while time.perf_counter() - started < limit:
        if any("standard-" not in path for path in glob.glob(str(cache / "modules" / "*" / "state.json"))):
            return round(time.perf_counter() - started, 3)
        time.sleep(0.05)
    return None


def ladder(tree, command, samples, interface=True, cache=None, after_cold=False):
    out = {"cold": run(command, tree.src)}
    if cache is not None:
        out["seeded_after_s"] = settle(cache)
        if out["seeded_after_s"] is None:
            raise RuntimeError("owned check seeder failed to finish before the deadline")
    if after_cold:
        out["after_cold"] = run(command, tree.src)
    out["noop_samples"] = [run(command, tree.src) for _ in range(samples)]
    out["noop"] = best(out["noop_samples"])
    bodies = []
    for _ in range(samples):
        tree.body_edit()
        bodies.append(run(command, tree.src))
    out["body_edit"] = best(bodies)
    out["body_edit_samples"] = bodies
    if interface:
        faces = []
        for _ in range(samples):
            tree.interface_edit()
            faces.append(run(command, tree.src))
        out["interface_edit"] = best(faces)
        out["interface_edit_samples"] = faces
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("tier")
    parser.add_argument("work")
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--label", default="")
    parser.add_argument("--json")
    parser.add_argument("--steps", default="check,test,build")
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("samples must be positive")
    mylang = str(Path(args.mylang).resolve())
    work = Path(args.work).resolve()
    scratch = work / "scratch"
    scratch.mkdir(parents=True, exist_ok=True)
    os.environ["TMPDIR"] = str(scratch)
    os.environ["MYLANG_MEASURE_TESTS"] = str(len(list(Path(args.tier).glob("m[0-9]*.my"))))
    result = {"label": args.label, "cpus": os.environ.get("MYLANG_MEASURE_CPUS", "2,3,10,11"), "tier": args.tier, "load_start": load()}
    steps = args.steps.split(",")
    if "check" in steps:
        tree = Tree(args.tier, work / "check")
        cache = tree.work / "cache"
        result["check"] = ladder(tree, [mylang, "check", "main.my", f"--cache-dir={cache}"], args.samples, cache=cache)
    if "test" in steps:
        tree = Tree(args.tier, work / "test")
        result["test"] = ladder(tree, [mylang, "test", "main.my", "--cache-dir", str(tree.work / "cache")], args.samples, interface=False, after_cold=True)
    if "build" in steps:
        tree = Tree(args.tier, work / "build")
        result["build"] = ladder(tree, [mylang, "build", "main.my", "--project", "-o", str(tree.work / "prog"), f"--cache-dir={tree.work / 'cache'}"], args.samples, interface=False)
    result["load_end"] = load()
    text = json.dumps(result, indent=1)
    if args.json:
        Path(args.json).write_text(text)
    print(text)


if __name__ == "__main__":
    main()
