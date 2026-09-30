#!/usr/bin/env python3
"""Measure module interfaces on a generated ladder tier (gen_scale.py).

usage: measure.py MYLANG TIER_DIR WORK_DIR [--samples N] [--module NAME]

TIER_DIR is a gen_scale.py mylang directory (m000.my ... main.my). For the tier
it reports, as one JSON object:

- emit: wall and peak RSS of `mylang interfaces emit` (whole-program check,
  two lowerings, every interface), and the artifact sizes: total, per module
  (mean, median, max) and declaration-text bytes;
- edit_check_whole: after a body edit in the middle module (the EDIT_BODY
  constant), the warm whole-program `mylang check` (with its frontend cache);
- edit_check_module: after the same edit, `mylang interfaces check` of that
  module from the stored interfaces (reads its own source and the interfaces
  it imports only);
- cutoff: whether the edited module's interface hash stayed the same and which
  implementation hashes changed after the edit;
- load: the 1-minute load average at the start and end.

Every timed command runs under `taskset -c 0-11`; each figure is the minimum
of --samples runs, with each run's own edit.
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import time
from pathlib import Path


def timed(cmd, cwd=None):
    started = time.perf_counter()
    proc = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M", "taskset", "-c", "0-11"] + cmd, cwd=cwd, capture_output=True, text=True)
    wall = time.perf_counter() - started
    rss = re.search(r"__RSS__ (\d+)", proc.stderr)
    return wall, int(rss.group(1)) if rss else None, proc


def edit(path, token):
    text = path.read_text()
    new, count = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", text, count=1)
    assert count == 1, "no EDIT_BODY marker"
    path.write_text(new)


def index(out):
    return {row["module"]: row for row in json.loads((out / "index.json").read_text())["modules"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("tier")
    parser.add_argument("work")
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--module")
    args = parser.parse_args()
    mylang = str(Path(args.mylang).resolve())
    work = Path(args.work).resolve()
    shutil.rmtree(work, ignore_errors=True)
    src = work / "src"
    shutil.copytree(args.tier, src)
    modules = sorted(p.stem for p in src.glob("m[0-9]*.my"))
    module = args.module or modules[len(modules) // 2]
    result = {"tier": str(args.tier), "modules": len(modules) + 1, "edited": module, "load_start": os.getloadavg()[0]}
    # Emit every interface from the whole-program check.
    emits = []
    for sample in range(args.samples):
        out = work / f"emit-{sample}"
        wall, rss, proc = timed([mylang, "interfaces", "emit", str(src / "main.my"), f"--out={out}"])
        assert proc.returncode == 0, proc.stderr[-800:]
        emits.append((wall, rss))
    out = work / "emit-0"
    rows = index(out)
    sizes = [row["bytes"] for row in rows.values()]
    texts = [row["counts"]["text_bytes"] for row in rows.values()]
    result["emit"] = {
        "wall_s": round(min(w for w, _ in emits), 3),
        "peak_rss_mb": round(min(r for _, r in emits) / 1024, 1),
        "artifact_bytes_total": sum(sizes),
        "artifact_bytes_mean": round(statistics.mean(sizes)),
        "artifact_bytes_median": statistics.median(sizes),
        "artifact_bytes_max": max(sizes),
        "text_bytes_total": sum(texts),
        "source_bytes_total": sum(p.stat().st_size for p in src.glob("*.my")),
        "stable_across_samples": all(index(work / f"emit-{s}") == rows for s in range(args.samples)),
    }
    # Warm the whole-program check's caches, then edit a body and re-check.
    cache = work / "cache"
    wall, rss, proc = timed([mylang, "check", str(src / "main.my"), f"--cache-dir={cache}"])
    assert proc.returncode == 0, proc.stderr[-800:]
    whole, single = [], []
    target = src / f"{module}.my"
    for sample in range(args.samples):
        edit(target, 9100 + sample)
        wall, rss, proc = timed([mylang, "check", str(src / "main.my"), f"--cache-dir={cache}"])
        assert proc.returncode == 0, proc.stderr[-800:]
        whole.append((wall, rss))
        wall, rss, proc = timed([mylang, "interfaces", "check", str(src / "main.my"), f"--module={module}", f"--from={out}"])
        assert proc.returncode == 0, proc.stdout[-800:] + proc.stderr[-800:]
        single.append((wall, rss, json.loads(proc.stdout)))
    result["edit_check_whole"] = {"wall_s": round(min(w for w, _ in whole), 3), "peak_rss_mb": round(min(r for _, r in whole) / 1024, 1)}
    best = min(single, key=lambda s: s[0])
    result["edit_check_module"] = {"wall_s": round(best[0], 3), "peak_rss_mb": round(min(s[1] for s in single) / 1024, 1),
                                   "stood_in": best[2]["stood_in"], "declared_only": best[2]["declared_only"], "functions": best[2]["functions"]}
    # Early cutoff: re-emit after the edits and compare hashes.
    after_out = work / "emit-after"
    wall, rss, proc = timed([mylang, "interfaces", "emit", str(src / "main.my"), f"--out={after_out}"])
    assert proc.returncode == 0, proc.stderr[-800:]
    after = index(after_out)
    result["cutoff"] = {
        "edited_interface_hash_unchanged": after[module]["interface_hash"] == rows[module]["interface_hash"],
        "interface_hashes_changed": sorted(m for m in rows if after[m]["interface_hash"] != rows[m]["interface_hash"]),
        "implementation_hashes_changed": sorted(m for m in rows if after[m]["implementation_hash"] != rows[m]["implementation_hash"]),
    }
    result["load_end"] = os.getloadavg()[0]
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
