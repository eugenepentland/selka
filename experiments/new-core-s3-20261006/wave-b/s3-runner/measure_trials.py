#!/usr/bin/env python3
"""Measure the real copied-value trial boundary, without compiler build time."""
import argparse
import json
import os
from pathlib import Path
import statistics
import struct
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", required=True)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    directory.mkdir(parents=True, exist_ok=False)
    rows = []
    for count in (12, 100, 1000):
        source = directory / f"{count}.input"
        source.write_bytes(struct.pack("<Q", count) + struct.pack("<QQQ", 2, 0, 0) * count)
        samples = []
        for repeat in range(3):
            response = directory / f"{count}-{repeat}.response"
            started = time.perf_counter()
            done = subprocess.run(["taskset", "-c", "10", str(Path(args.executable).resolve()), "0", str(source), str(response)], env=dict(os.environ, MYL_CORE_LEAKCHECK="1"), capture_output=True, timeout=60)
            samples.append(time.perf_counter() - started)
            if done.returncode != 0 or done.stdout or done.stderr:
                raise ValueError((done.returncode, done.stdout, done.stderr))
            expected = struct.pack("<QQQQQQQ", 0, 16, 1, 0, 0, 0, 0) * count
            if response.read_bytes() != expected:
                raise ValueError("a measured trial failed to answer True with clean output")
        median = statistics.median(samples)
        rows.append({"trials": count, "outer_batches": 1, "trial_forks": count, "seconds": samples, "median_seconds": median, "microseconds_per_trial": median * 1e6 / count})
    result = {"cpu": 10, "includes": "process start, per-trial fork, capture files, copied-value decode/encode and cleanup; excludes compiler build", "rows": rows}
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
