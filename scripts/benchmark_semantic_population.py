#!/usr/bin/env python3
"""Measure filesystem inventory growth while populating fresh semantic caches.

R4 corrective benchmark. Each sample writes a fresh N-body module (N-1 helpers
plus main), runs `selka project-dependencies` under `strace -f -c` against a
fresh independent `--cache-dir`, and records the `statx`/`getdents64` syscall
counts. The retired per-body trim produced ~N^2/2 `statx` calls; the publication
batch is expected to stay approximately linear.

Invocation (from the worktree root, after `zig build`):

    python3 scripts/benchmark_semantic_population.py \
        --compiler zig-out/bin/selka --sizes 128 256 512 1024

Options are bounded: sizes default to 128 256 512, are capped at 4096, and each
sample is a single fresh process. Raw counts are printed and can be redirected.

Exit status is non-zero when any sample fails or when the measured growth is not
approximately linear (each doubling should multiply `statx` by roughly 2, not 4).
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_SIZE = 4096
SUMMARY_NAMES = ("statx", "newfstatat", "getdents64")


def generate_source(size: int) -> str:
    lines = ["", ""]
    for i in range(size - 1):
        lines += [f"func f{i}(x: int) -> int effects():", f"    return x + {i}", ""]
    lines += ["func main() -> int effects():", "    total = 0"]
    for i in range(size - 1):
        lines.append(f"    total = total + f{i}({i})")
    lines += ["    return total", ""]
    return "\n".join(lines)


def measure(compiler: Path, size: int, work: Path) -> dict:
    source_dir = work / f"scale-{size}"
    source_dir.mkdir(parents=True, exist_ok=True)
    source = source_dir / "main.selka"
    source.write_text(generate_source(size))
    cache = work / f"cache-{size}"
    shutil.rmtree(cache, ignore_errors=True)
    trace = work / f"strace-{size}.txt"
    command = [
        "strace",
        "-f",
        "-c",
        "-e",
        "trace=statx,newfstatat,getdents64",
        "-o",
        str(trace),
        str(compiler),
        "project-dependencies",
        str(source),
        "--report",
        f"--cache-dir={cache}",
    ]
    completed = subprocess.run(command, cwd=source_dir, capture_output=True, text=True, timeout=300, check=False)
    counts = {name: 0 for name in SUMMARY_NAMES}
    if trace.exists():
        for line in trace.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[-1] in counts and parts[-3].isdigit():
                counts[parts[-1]] = int(parts[-3])
    checked = 0
    found = re.search(r'"checked_bodies":\{"status":"miss","performed":(\d+)', completed.stderr)
    if found:
        checked = int(found.group(1))
    return {
        "size": size,
        "code": completed.returncode,
        "statx": counts["statx"],
        "newfstatat": counts["newfstatat"],
        "getdents64": counts["getdents64"],
        "checked_bodies": checked,
        "seconds": None,
        "trace": str(trace),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", type=Path, default=Path("zig-out/bin/selka"))
    parser.add_argument("--sizes", type=int, nargs="+", default=[128, 256, 512])
    parser.add_argument("--work-dir", type=Path, default=Path(tempfile.gettempdir()) / "selka-r4-population")
    parser.add_argument("--max-size", type=int, default=MAX_SIZE)
    args = parser.parse_args()

    if any(size < 2 or size > args.max_size for size in args.sizes):
        parser.error(f"sizes must be between 2 and {args.max_size} (bounded benchmark)")
    compiler = args.compiler.resolve()
    if not compiler.exists():
        parser.error(f"compiler not found: {compiler}")
    shutil.rmtree(args.work_dir, ignore_errors=True)
    args.work_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for size in args.sizes:
        row = measure(compiler, size, args.work_dir)
        rows.append(row)
        print(f"N={size:5d} code={row['code']} statx={row['statx']:9d} "
              f"newfstatat={row['newfstatat']:5d} getdents64={row['getdents64']:5d} "
              f"checked={row['checked_bodies']}", flush=True)

    failures = [row for row in rows if row["code"] != 0 or row["checked_bodies"] != row["size"]]
    ratios = []
    for previous, current in zip(rows, rows[1:]):
        if previous["statx"] > 0 and current["size"] == previous["size"] * 2:
            ratios.append(current["statx"] / previous["statx"])
    print(json.dumps({"rows": rows, "doubling_ratios": ratios}, indent=2))
    if failures:
        print("FAILED: one or more samples did not populate", file=sys.stderr)
        return 1
    if ratios and max(ratios) > 3.0:
        print(f"FAILED: statx growth looks super-linear (doubling ratios {ratios})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
