#!/usr/bin/env python3
"""Pin split-key ownership edge cases against the corrected old oracle and all Core modes."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
EXPECTED = "0 5 2 1 1\n13 2 9 2\n3 1 1 1\n4 2 2 1 2\n2 2 1\n3 1 1 1\n3 1 1 1\n"


def command(argv, directory, environment=None):
    started = time.monotonic()
    done = subprocess.run(list(map(str, argv)), capture_output=True, text=True, env=environment)
    record = {"command": list(map(str, argv)), "status": done.returncode,
              "stdout": done.stdout, "stderr": done.stderr,
              "seconds": time.monotonic() - started}
    directory.write_text(json.dumps(record, indent=2) + "\n")
    if done.returncode:
        raise RuntimeError(f"command failed: {record}")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    evidence.relative_to(ROOT)
    evidence.mkdir(parents=True, exist_ok=False)
    source = ROOT / "experiments/new-core-s3-20261006/wave-c/s3-a/split-keys-03.my"
    binaries = ROOT / ".mylang-cache/s3-a" / evidence.name
    binaries.mkdir(parents=True, exist_ok=False)
    configurations = [
        ("old", ROOT / ".mylang-cache/s3-a/oracle/mylang", ["--release"]),
        ("debug", ROOT / "zig-out/bin/mylang-core", []),
        ("release", ROOT / "zig-out/bin/mylang-core", ["--release"]),
        ("verify", ROOT / "zig-out/bin/mylang-core", ["--release", "--verify-facts"]),
    ]
    summary = {"qualified": False, "expected": EXPECTED, "runs": [], "error": None}
    try:
        for name, compiler, mode in configurations:
            output = binaries / name
            command([compiler, "build", source, "-o", output, "--cache-dir", binaries / f"cache-{name}", *mode], evidence / f"build-{name}.json")
            environment = dict(os.environ)
            if name != "old":
                environment["MYL_CORE_LEAKCHECK"] = "1"
            result = command([output], evidence / f"run-{name}.json", environment)
            if result["stdout"] != EXPECTED or result["stderr"]:
                raise RuntimeError(f"output or leak mismatch for {name}: {result}")
            summary["runs"].append(name)
            print(f"{name}: exact output, zero exit, empty stderr", flush=True)
        summary["qualified"] = True
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
