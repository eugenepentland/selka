#!/usr/bin/env python3
"""Measure the per-module build (MODULE-COMPILE-1) on a generated ladder tier.

usage: measure.py MYLANG TIER_DIR WORK_DIR [--samples N] [--module NAME]

TIER_DIR is a gen_scale.py mylang directory (m000.my ... main.my). The script
copies it to WORK_DIR/src, then:

1. cold: compiles every module in import order with `compile-module
   --objects` (sequentially: the tier is one import chain) and links with
   `link-modules --report`; reports the sum and the largest single compile;
2. edit: for each sample, writes a new constant into the EDIT_BODY line of the
   middle module (a body edit), then times, each under `taskset -c 0-11` with
   `/usr/bin/time` for the peak RSS:
   - `compile-module` of that module without objects (check, lowering,
     emission, interface),
   - the same with `--objects` (plus its batch objects in the build cache),
   - `link-modules --report` (merge every module's units, then the ordinary
     driver: key every unit, reuse every object, compile the shared unit if
     its text changed, link),
   - the whole-program `build --project` of the same edit with its own warm
     cache, for reference;
   and records whether the module's interface, emission and positions hashes
   held (so no dependent needs compiling);
3. load: the 1-minute load average at the start and end.

Each timed figure is the minimum over the samples (each with its own edit).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def timed(cmd, cwd=None):
    started = time.perf_counter()
    proc = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M", "taskset", "-c", "0-11"] + cmd, cwd=cwd, capture_output=True, text=True)
    wall = time.perf_counter() - started
    rss = re.search(r"__RSS__ (\d+)", proc.stderr)
    if proc.returncode != 0:
        raise SystemExit(f"failed: {' '.join(cmd)}\n{proc.stderr[-2000:]}")
    return wall, int(rss.group(1)) if rss else None, proc


def edit(path, token):
    text = path.read_text()
    new, count = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", text, count=1)
    assert count == 1, "no EDIT_BODY marker"
    path.write_text(new)


def order_of(src):
    """Import order of a gen_scale tier: m000 .. mNNN, then main."""
    modules = sorted(p.stem for p in src.glob("m[0-9]*.my"))
    return modules + ["main"]


def report_line(stdout):
    return next((json.loads(line) for line in stdout.splitlines() if line.startswith('{"version":"qbe-build-v1"')), {})


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
    entry = str(src / "main.my")
    result = {"tier": str(args.tier), "load_start": os.getloadavg()[0]}
    common = [f"--interfaces={work / 'if'}", f"--out={work / 'out'}", f"--cache-dir={work / 'cache'}", "--arenas=off"]
    order = order_of(src)
    middle = args.module or order[(len(order) - 1) // 2]
    # 1. cold
    cold = []
    for module in order:
        wall, rss, _ = timed([mylang, "compile-module", entry, f"--module={module}", "--objects"] + common)
        cold.append((wall, rss, module))
    wall, rss, proc = timed([mylang, "link-modules", entry, f"--units={work / 'out'}", "-o", str(work / "program"), f"--cache-dir={work / 'cache'}", "--report"])
    build = report_line(proc.stdout)
    result["cold"] = {
        "modules": len(order),
        "compile_sum_s": round(sum(w for w, _, _ in cold), 3),
        "compile_max_s": round(max(w for w, _, _ in cold), 3),
        "compile_max_rss_mb": round(max(r for _, r, _ in cold) / 1024, 1),
        "link_s": round(wall, 3),
        "link_rss_mb": round(rss / 1024, 1),
        "link_compiled_function_objects": build.get("compiled_function_objects"),
    }
    # The whole-program reference, warmed on the same sources.
    whole_cache = work / "whole-cache"
    timed([mylang, "build", entry, "--project", "-o", str(work / "whole"), f"--cache-dir={whole_cache}"])
    # 2. edits
    samples = []
    path = src / f"{middle}.my"
    for sample in range(args.samples):
        edit(path, 9100 + sample)
        plain_wall, plain_rss, proc = timed([mylang, "compile-module", entry, f"--module={middle}"] + common)
        before = json.loads(proc.stdout)["hashes"]
        edit(path, 9200 + sample)
        objects_wall, objects_rss, proc = timed([mylang, "compile-module", entry, f"--module={middle}", "--objects"] + common)
        summary = json.loads(proc.stdout)
        link_wall, link_rss, proc = timed([mylang, "link-modules", entry, f"--units={work / 'out'}", "-o", str(work / "program"), f"--cache-dir={work / 'cache'}", "--report"])
        build = report_line(proc.stdout)
        whole_wall, whole_rss, _ = timed([mylang, "build", entry, "--project", "-o", str(work / "whole"), f"--cache-dir={whole_cache}"])
        samples.append({
            "compile_s": plain_wall, "compile_rss_mb": plain_rss / 1024,
            "compile_objects_s": objects_wall, "compile_objects_rss_mb": objects_rss / 1024,
            "link_s": link_wall, "link_rss_mb": link_rss / 1024,
            "link_codegen_s": build.get("codegen_seconds"), "link_link_s": build.get("link_seconds"),
            "link_compiled_function_objects": build.get("compiled_function_objects"),
            "metadata_reused": build.get("metadata_reused"),
            "whole_build_s": whole_wall, "whole_build_rss_mb": whole_rss / 1024,
            "interface_held": before["interface"] == summary["hashes"]["interface"],
            "emission_held": before["emission"] == summary["hashes"]["emission"],
            "positions_held": before["positions"] == summary["hashes"]["positions"],
            "counts": summary["counts"],
        })
    keys = [k for k in samples[0] if k.endswith("_s") or k.endswith("_mb")]
    result["edit"] = {k: round(min(s[k] for s in samples if s[k] is not None), 3) for k in keys if any(s[k] is not None for s in samples)}
    result["edit"]["module"] = middle
    for flag in ("interface_held", "emission_held", "positions_held", "metadata_reused"):
        result["edit"][flag] = all(s[flag] for s in samples)
    result["edit"]["link_compiled_function_objects"] = max(s["link_compiled_function_objects"] or 0 for s in samples)
    result["edit"]["counts"] = samples[-1]["counts"]
    result["samples"] = samples
    result["load_end"] = os.getloadavg()[0]
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
