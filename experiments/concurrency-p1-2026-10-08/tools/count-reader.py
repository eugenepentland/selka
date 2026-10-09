#!/usr/bin/env python3
"""Reproduce P1's emitted uniqueness-read race; run the atomic-load control.

From the repository root: python3 experiments/concurrency-p1-2026-10-08/tools/count-reader.py
Every compilation uses build-slot; all scratch and caches are on disk.
This is an isolated ABI probe, not the P1-5 concurrency suite.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent / "evidence"
SCRATCH = ROOT / ".tmp" / "concurrency-p1-count-reader"
SCRATCH.mkdir(parents=True, exist_ok=True)
EVIDENCE.mkdir(exist_ok=True)
env = dict(os.environ, TMPDIR=str(SCRATCH),
           ZIG_LOCAL_CACHE_DIR=str(ROOT / ".zig-cache"),
           ZIG_GLOBAL_CACHE_DIR=str(ROOT.parent / ".zig-global-cache"))
emitter = (ROOT / "src/core/emit_llvm.zig").read_text()
assert 'const count_load_line = "  {s} = load i32, ptr {s}, align 8, "' in emitter
assert 'count_load_line ++ "  {s} = icmp eq i32 {s}, 1' in emitter
summary = {"toolchain": subprocess.check_output(["zig", "version"], text=True).strip(),
           "source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
           "variants": {}}
for variant, load, repeats in (("plain", "load i32, ptr %block", 1),
                               ("atomic", "load atomic i32, ptr %block monotonic", 100)):
    ir = f'''target triple = "x86_64-unknown-linux-gnu"
define zeroext i1 @p1_is_unique(ptr %block) noinline sanitize_thread {{
  %rc = {load}, align 8, !tbaa !3, !range !8
  %unique = icmp eq i32 %rc, 1
  ret i1 %unique
}}
!1 = !{{!"myl.tbaa"}}
!2 = !{{!"myl.count", !1, i64 0}}
!3 = !{{!2, !2, i64 0}}
!8 = !{{i32 1, i32 0}}
'''
    source = EVIDENCE / f"count-reader-{variant}.ll"
    source.write_text(ir)
    binary = SCRATCH / variant
    command = [str(ROOT / "scripts/build-slot.sh"), "build", "zig", "cc",
               "-O1", "-g", "-fsanitize=thread", "-pthread",
               str(HERE / "count-reader.c"), str(source), "-o", str(binary)]
    built = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    (EVIDENCE / f"count-reader-{variant}-build.log").write_text(built.stdout + built.stderr)
    built.check_returncode()
    results = []
    for repetition in range(repeats):
        ran = subprocess.run([str(binary)], cwd=ROOT, env=dict(env, TSAN_OPTIONS="halt_on_error=1:exitcode=66"),
                             capture_output=True, text=True, timeout=60)
        if repetition == 0 or ran.returncode:
            (EVIDENCE / f"count-reader-{variant}-{repetition:03}.log").write_text(ran.stdout + ran.stderr)
        results.append({"repetition": repetition, "exit": ran.returncode,
                        "race": "WARNING: ThreadSanitizer: data race" in ran.stderr,
                        "stdout": ran.stdout.strip()})
        if variant == "atomic" and ran.returncode:
            break
    summary["variants"][variant] = results
    print(variant, "runs", len(results), "exits", sorted(set(r["exit"] for r in results)), flush=True)
(EVIDENCE / "count-reader.json").write_text(json.dumps(summary, indent=2) + "\n")
assert summary["variants"]["plain"][0]["race"], "The plain-load race was not reproduced"
assert len(summary["variants"]["atomic"]) == 100
assert all(r["exit"] == 0 and r["stdout"] == "unique=0 count=80000002"
           for r in summary["variants"]["atomic"])
