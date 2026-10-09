#!/usr/bin/env python3
"""Measure a built compiler; host build time is deliberately not frontend time."""
import argparse
import hashlib
from datetime import datetime, timezone
import json
import platform
import re
import statistics
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=Path("zig-out/bin/selka"))
    parser.add_argument("--mode", required=True, choices=["Debug", "ReleaseFast"])
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--sizes", type=int, nargs="+", default=[100, 1000, 10000])
    args = parser.parse_args()
    if args.repeats <= 0 or any(n <= 0 for n in args.sizes):
        parser.error("repeats and sizes must be positive")
    compiler = args.compiler.resolve(strict=True)
    cpu = platform.processor()
    cpuinfo = Path("/proc/cpuinfo")
    if not cpu and cpuinfo.exists():
        cpu = next((line.split(":", 1)[1].strip() for line in cpuinfo.read_text().splitlines() if line.startswith("model name")), "unknown")
    report = {
        "experiment": "duplicate-discovery",
        "machine": platform.platform(),
        "processor": cpu,
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "zig": subprocess.check_output(["zig", "version"], text=True).strip(),
        "host_mode_declared": args.mode,
        "scope": "frontend=lex/parse/check; discovery=canonicalization/index; excludes host build, input I/O, source copying, rendering, lowering, VM execution",
        "rows": [],
    }
    with tempfile.TemporaryDirectory(prefix="selka-discovery-bench-") as directory:
        source = Path(directory) / "generated.selka"
        for size in args.sizes:
            # A bounded set of repeated policies creates large groups, testing
            # that reporting does not construct every possible matching pair.
            source.write_text("".join(
                f"func f{i}(x: i64) -> i64:\n    const y = x * 2\n    return y + {i % 31}\n\n\n"
                for i in range(size)
            ) + 'func main() -> i64:\n    return f0(3)\n')
            samples = []
            for _ in range(args.repeats):
                outcome = subprocess.run(
                    [str(compiler), "discover-duplicates", str(source), "--population=generated", "--timings"],
                    check=True, text=True, capture_output=True,
                )
                analysis_version = re.search(r"^duplicate discovery ([^;]+);", outcome.stdout)
                if not analysis_version:
                    raise RuntimeError("missing analysis version")
                report["analysis_version"] = analysis_version[1]
                match = re.search(r"^timings: (.+)$", outcome.stderr, re.MULTILINE)
                if not match:
                    raise RuntimeError("missing timing output")
                samples.append({k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", match[1])})
            report["rows"].append({
                "helpers": size,
                "samples": samples,
                "median_frontend_ns": statistics.median(s["frontend_ns"] for s in samples),
                "median_discovery_ns": statistics.median(s["discovery_ns"] for s in samples),
            })
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
