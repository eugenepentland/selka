#!/usr/bin/env python3
"""Build and compare a bounded nbody input with two immutable Debug compilers."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess


def execute(command):
    run = subprocess.run(command, text=True, capture_output=True)
    row = dict(command=command, status=run.returncode, stdout=run.stdout, stderr=run.stderr)
    assert run.returncode == 0, row
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--steps", type=int, default=10000)
    parser.add_argument("--cpu", type=int, default=10)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = (root / "bench/parity/suite/nbody.my").read_text()
    assert source.count("steps = 5000000") == 1 and args.steps > 0
    guest = output / "nbody.my"
    guest.write_text(source.replace("steps = 5000000", "steps = " + str(args.steps)))
    receipt = {"steps": args.steps, "runs": [], "medians": {}}
    expected = None
    for backend in ("qbe", "llvm"):
        for side in ("before", "after"):
            compiler = getattr(args, side).resolve()
            binary = output / (side + "-" + backend)
            command = [str(compiler), "build", str(guest), "-o", str(binary),
                       "--cache-dir=" + str(output / "cache"), "--rc-runtime", "--keep-symbols"]
            command += ["--release"] if backend == "llvm" else ["--mode", "ReleaseFast"]
            build = execute([str(root / "scripts/build-slot.sh"), "build"] + command)
            build["compiler_sha256"] = hashlib.sha256(compiler.read_bytes()).hexdigest()
            build["binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
            receipt["runs"].append(build)
            counts = []
            for repeat in range(3):
                stat = output / f"{side}-{backend}-{repeat}.stat"
                row = execute(["taskset", "-c", str(args.cpu), "perf", "stat", "-x,", "-e",
                               "instructions:u", "-o", str(stat), str(binary)])
                if expected is None:
                    expected = row["stdout"]
                assert row["stdout"] == expected, row
                row["perf"] = stat.read_text()
                count = next(int(line.split(",")[0]) for line in row["perf"].splitlines()
                             if "instructions" in line and line.split(",")[0].isdigit())
                row.update(side=side, backend=backend, repeat=repeat, instructions=count)
                counts.append(count)
                receipt["runs"].append(row)
            receipt["medians"][side + "-" + backend] = statistics.median(counts)
            (output / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(backend, receipt["medians"]["after-" + backend] /
              receipt["medians"]["before-" + backend], flush=True)


if __name__ == "__main__":
    main()
