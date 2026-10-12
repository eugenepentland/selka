#!/usr/bin/env python3
"""Check all existing A06-owned examples without requiring live host providers."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
EXAMPLES = ("examples/python-word-count/main.my", "examples/domain-codecs/main.my",
            "examples/external-capabilities/main.my", "examples/generic-resources.my")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--examples", default=",".join(EXAMPLES))
    parser.add_argument("--default", action="store_true")
    args = parser.parse_args()
    compiler, output = args.compiler.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "scope": "source checking only; no runtime qualification of live host providers", "cases": {}}
    for relative in args.examples.split(","):
        command = [str(ROOT / "scripts/build-slot.sh"), "build", str(compiler), "check", relative,
                   *([] if args.default else ["--experimental-zero-rc"])]
        ran = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=1800)
        report["cases"][relative] = {"command": command,
            "source_sha256": hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(),
            "status": ran.returncode, "stdout": ran.stdout, "stderr": ran.stderr}
        print(relative, ran.returncode, flush=True)
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    return int(any(case["status"] for case in report["cases"].values()))


if __name__ == "__main__":
    raise SystemExit(main())
