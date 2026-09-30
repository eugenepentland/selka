#!/usr/bin/env python3
"""Measure `mylang build` of a generated ladder tier: cold, no-op, body edit and
interface edit, each with its wall time and the largest process's peak RSS.

usage: measure.py MYLANG TIER_DIR WORK_DIR [--samples N] [--label L]
                  [--extra ARG]... [--json OUT]

TIER_DIR is a gen_scale.py mylang directory (m000.my ... main.my). The script
copies it to WORK_DIR/src and runs, each under `taskset -c 0-11` and
`/usr/bin/time` (whose %M is the largest single process of the tree: the
driver, a module compile, QBE, the assembler or the linker):

- cold: `build main.my --project -o WORK/prog --cache-dir=WORK/cache
  --timings=json [EXTRA]` over an empty cache;
- no-op: the same build again;
- body edit: for each sample, a new constant in the EDIT_BODY line of the
  middle module, then the build;
- interface edit: for each sample, a new public function appended to the
  middle module, then the build.

Pass `--extra=--whole-program` for the whole-program build of a compiler that
builds module by module by default. Each edit figure is the minimum over the
samples. For a per-module build it also counts the modules each build compiled
(the `*.result.json` files it rewrote) and reads the phases from
`--timings=json` (`frontend` is the scheduler and every module compile,
`codegen` the shared metadata unit, entry and runtime, `link` the static link).
The 1-minute load average is recorded at the start and the end.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def run(cmd, cwd):
    started = time.perf_counter()
    proc = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M", "taskset", "-c", "0-11"] + cmd, cwd=cwd, capture_output=True, text=True)
    wall = time.perf_counter() - started
    rss = re.search(r"__RSS__ (\d+)", proc.stderr)
    if proc.returncode != 0:
        raise SystemExit(f"failed: {' '.join(cmd)}\n{proc.stderr[-3000:]}")
    phases = {}
    for name, ns in re.findall(r'"name":"([a-z_]+)","duration_ns":(\d+)', proc.stdout + proc.stderr):
        phases[name] = int(ns) / 1e9
    return {"wall_s": round(wall, 3), "rss_mb": round(int(rss.group(1)) / 1024, 1) if rss else None, "phases": {k: round(v, 3) for k, v in phases.items()}}


def load():
    return float(open("/proc/loadavg").read().split()[0])


class Tier:
    def __init__(self, args):
        self.mylang = str(Path(args.mylang).resolve())
        self.work = Path(args.work).resolve()
        shutil.rmtree(self.work, ignore_errors=True)
        self.work.mkdir(parents=True)
        self.src = self.work / "src"
        shutil.copytree(args.tier, self.src)
        modules = sorted(p.stem for p in self.src.glob("m[0-9]*.my"))
        self.middle = self.src / f"{modules[len(modules) // 2]}.my"
        self.cache = self.work / "cache"
        self.extra = args.extra or []

    def build(self):
        since = time.time()
        out = run([self.mylang, "build", "main.my", "--project", "-o", str(self.work / "prog"), f"--cache-dir={self.cache}", "--timings=json"] + self.extra, self.src)
        results = list((self.cache / "modules").glob("*/out/*.result.json")) if (self.cache / "modules").exists() else []
        if results:
            out["compiled_modules"] = sum(1 for p in results if p.stat().st_mtime >= since)
        return out

    def body_edit(self, token):
        text = self.middle.read_text()
        new, count = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", text, count=1)
        assert count == 1, "no EDIT_BODY marker"
        self.middle.write_text(new)

    def interface_edit(self, number):
        with self.middle.open("a") as out:
            out.write(f"\n\npublic def zz_added_{number}(n: int) -> int:\n    return n + {number}\n")


def best(samples):
    return min(samples, key=lambda s: s["wall_s"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("tier")
    parser.add_argument("work")
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--label", default="")
    parser.add_argument("--extra", action="append")
    parser.add_argument("--json")
    args = parser.parse_args()
    tier = Tier(args)
    result = {"label": args.label, "tier": str(Path(args.tier).resolve()), "extra": tier.extra, "middle": tier.middle.stem, "load_start": load()}
    result["cold"] = tier.build()
    result["noop"] = best([tier.build() for _ in range(args.samples)])
    bodies = []
    for sample in range(args.samples):
        tier.body_edit(9100 + sample)
        bodies.append(tier.build())
    result["body_edit"] = best(bodies)
    result["body_edit_samples"] = [s["wall_s"] for s in bodies]
    interfaces = []
    for sample in range(args.samples):
        tier.interface_edit(sample)
        interfaces.append(tier.build())
    result["interface_edit"] = best(interfaces)
    result["interface_edit_samples"] = [s["wall_s"] for s in interfaces]
    result["peak_rss_mb"] = max(s["rss_mb"] or 0 for s in [result["cold"], result["noop"]] + bodies + interfaces)
    result["load_end"] = load()
    text = json.dumps(result, indent=1)
    if args.json:
        Path(args.json).write_text(text)
    print(text)


if __name__ == "__main__":
    main()
