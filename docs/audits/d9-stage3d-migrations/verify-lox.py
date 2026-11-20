#!/usr/bin/env python3
"""Check the 13 pinned Lox scripts against the pinned expected output.

Usage: verify-lox.py BINARY WORK [--engine vm|tree|both] [--size smoke|tree|vm]
WORK is the directory passed to apply-lox.sh. An exit status of zero means
every selected engine/script returned zero and matched its expected bytes.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("work", type=Path)
    parser.add_argument("--engine", choices=("vm", "tree", "both"), default="vm")
    parser.add_argument("--size", choices=("smoke", "tree", "vm"), default="smoke")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    binary = args.binary.resolve()
    bench = args.work / "lox" / "bench"
    sizes = json.loads((bench / "sizes.json").read_text())
    generated = args.work / "stage3d-script-inputs"
    generated.mkdir(exist_ok=True)
    engines = ("vm", "tree") if args.engine == "both" else (args.engine,)
    passed = 0
    for source in sorted((bench / "scripts").glob("*.lox")):
        first, rest = source.read_text().split("\n", 1)
        if not first.startswith("var N = "):
            raise ValueError(f"unexpected script header: {source}")
        adjusted = generated / source.name
        adjusted.write_text(f"var N = {sizes[source.stem][args.size]};\n" + rest)
        expected = (bench / "expected" / f"{source.stem}.{args.size}.out").read_bytes()
        for engine in engines:
            try:
                result = subprocess.run(
                    (str(binary), f"--engine={engine}", str(adjusted.resolve())),
                    capture_output=True,
                    timeout=args.timeout,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                print(f"FAIL {engine} {source.stem}: timed out", file=sys.stderr)
                return 1
            if result.returncode != 0 or result.stdout != expected:
                print(f"FAIL {engine} {source.stem}: exit {result.returncode}", file=sys.stderr)
                print(f"expected={expected[:300]!r}", file=sys.stderr)
                print(f"actual={result.stdout[:300]!r}", file=sys.stderr)
                print(f"stderr={result.stderr[:300]!r}", file=sys.stderr)
                return 1
            passed += 1
            print(f"PASS {engine} {source.stem}", flush=True)
    print(f"{passed}/{passed} Lox script runs passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
