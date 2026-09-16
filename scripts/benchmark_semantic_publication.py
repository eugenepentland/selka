#!/usr/bin/env python3
"""Measure semantic-cache publication cost across filesystems.

Generates a bounded N-body project (default 101 bodies, matching the diagnostic
probe) and runs `check-project --report --timings=json` with a fresh private
`--cache-dir` for each cold sample. Records wall time, the exclusive
`retention_store_io` phase (publication), cache bytes/files, and, when `strace`
is available, the `fsync`/`fdatasync`/`syncfs` syscall counts for one cold run.

Publication batches publish a whole request's fresh bodies with one shared
filesystem sync, so the sync count must stay O(1) in the number of bodies and
independent of the filesystem, while `retention_store_io` on a slow metadata
filesystem must stop scaling with the body count.

Invocation (from the worktree root, after building a compiler):

    python3 scripts/benchmark_semantic_publication.py \
        --compiler /tmp/vel-rf-pub/bin/mylang \
        --output publication-probe.json \
        --roots tmpfs:/tmp ext4:/home/epentland/ai/canopy
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SOURCE_HEAD = "module main\n\n"


def generate_source(bodies: int) -> str:
    lines = [SOURCE_HEAD.rstrip("\n"), ""]
    for index in range(bodies - 1):
        lines += [f"def helper{index}() -> int effects():", f"    return {index}", ""]
    lines += ["def main() -> int:", f"    return helper{bodies - 2}()", ""]
    return "\n".join(lines)


def parse_phases(stderr: str) -> dict:
    phases = {}
    for line in stderr.splitlines():
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("version") == "phase-timings-v1":
            phases[record["name"]] = record.get("duration_ns", 0) / 1e6
    return phases


def cache_inventory(root: Path) -> dict:
    files = 0
    total = 0
    if root.exists():
        for path in root.rglob("*"):
            if path.is_file():
                files += 1
                total += path.stat().st_size
    return {"files": files, "bytes": total}


def run_once(compiler: Path, entry: Path, cache: Path, *, no_cache: bool, timeout: float, env: dict) -> dict:
    command = [str(compiler), "check-project", str(entry), "--report", "--timings=json"]
    command += ["--no-cache"] if no_cache else ["--cache-dir=" + str(cache)]
    begin = time.monotonic()
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)
    wall_ms = (time.monotonic() - begin) * 1000
    phases = parse_phases(result.stderr)
    return {
        "command": command,
        "exit": result.returncode,
        "wall_ms": wall_ms,
        "retention_store_io_ms": phases.get("retention_store_io", 0.0),
        "dependency_key_preparation_ms": phases.get("dependency_key_preparation", 0.0),
        "total_phase_ms": phases.get("total", 0.0),
        "cache": cache_inventory(cache),
        "stderr_tail": result.stderr[-400:] if result.returncode != 0 else "",
    }


SUMMARY_LINE = re.compile(r"^\s*[\d.]+\s+[\d.]+\s+\d+\s+(\d+)\s+(?:\d*|-)\s+(fsync|fdatasync|syncfs)\s*$")


def run_traced(compiler: Path, entry: Path, cache: Path, *, timeout: float, env: dict) -> dict:
    base = [str(compiler), "check-project", str(entry), "--report", "--timings=json", "--cache-dir=" + str(cache)]
    trace_path = Path(str(cache) + ".trace")
    command = ["strace", "-f", "-c", "-e", "trace=fsync,fdatasync,syncfs", "-o", str(trace_path)] + base
    begin = time.monotonic()
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return {"exit": None, "wall_ms": None, "syscalls": None, "strace_available": False}
    wall_ms = (time.monotonic() - begin) * 1000
    counts = {}
    if trace_path.exists():
        for line in trace_path.read_text().splitlines():
            match = SUMMARY_LINE.match(line)
            if match:
                counts[match.group(2)] = int(match.group(1))
    return {
        "exit": result.returncode,
        "wall_ms": wall_ms,
        "retention_store_io_ms": parse_phases(result.stderr).get("retention_store_io", 0.0),
        "syscalls": counts,
        "strace_available": result.returncode == 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--roots", nargs="+", default=["tmpfs:/tmp", "ext4:/home/epentland/ai/canopy"],
                        help="LABEL:PARENT pairs; one private directory is created under each parent")
    parser.add_argument("--bodies", type=int, default=101)
    parser.add_argument("--cold-samples", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()
    if args.bodies < 2:
        raise SystemExit("--bodies must be at least 2")

    compiler = args.compiler.resolve()
    source = generate_source(args.bodies)
    env = dict(os.environ)
    env["MYLANG_SEMANTIC_BUDGET"] = "16777216"
    document = {
        "version": "semantic-publication-probe-v1",
        "compiler": str(compiler),
        "compiler_sha256": __import__("hashlib").sha256(compiler.read_bytes()).hexdigest(),
        "bodies": args.bodies,
        "source_bytes": len(source.encode()),
        "host_load_before": Path("/proc/loadavg").read_text().strip(),
        "filesystems": [],
    }
    for spec in args.roots:
        label, _, parent = spec.partition(":")
        base = Path(tempfile.mkdtemp(prefix=".mylang-publication-", dir=parent))
        entry = base / "main.my"
        entry.write_text(source)
        record = {"label": label, "root": str(base), "states": []}
        nocache = run_once(compiler, entry, base / "nocache", no_cache=True, timeout=args.timeout, env=env)
        record["states"].append({"state": "no_cache", **nocache})
        for index in range(args.cold_samples):
            cold = run_once(compiler, entry, base / f"cold-{index}", no_cache=False, timeout=args.timeout, env=env)
            record["states"].append({"state": f"cold_{index}", **cold})
        traced = run_traced(compiler, entry, base / "cold-trace", timeout=args.timeout, env=env)
        record["states"].append({"state": "cold_trace", **traced})
        document["filesystems"].append(record)
        print(f"[publication] {label}: " + ", ".join(
            f"{item['state']}={item.get('retention_store_io_ms', item.get('wall_ms')):.1f}ms"
            for item in record["states"]), flush=True)
        shutil.rmtree(base, ignore_errors=True)
    document["host_load_after"] = Path("/proc/loadavg").read_text().strip()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n")
    print(json.dumps({"output": str(args.output)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
