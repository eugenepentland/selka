#!/usr/bin/env python3
"""Qualify pure Selka tests and the installed native protocol boundary."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", required=True)
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--component-dir", type=Path, required=True)
    args = parser.parse_args()
    output = subprocess.check_output([args.builder, "--root", ROOT,
        "--zig", args.zig, "--seed-only"], text=True)
    seed = Path(output.strip().splitlines()[-1])
    environment = {name: value for name, value in os.environ.items()
                   if not name.startswith("MYLANG_") and name != "ZIG"}
    environment.update(MYLANG_ZIG=args.zig, MYLANG_CORE_RUNTIME_CACHE="", MYL_CORE_LEAKCHECK="1")
    for source, name in (("test_index", "test-index"), ("cache_plan", "cache-plan")):
        oracle = ROOT / f"selfhost/tests/run_{source}_component.py"
        with tempfile.TemporaryDirectory(prefix="selka-component-tests-") as temporary:
            for flags in ([], ["--release"]):
                subprocess.run([seed, "test", ROOT / f"selfhost/components/{source}/tests.my",
                    "--no-cache", "--cache-dir", temporary, "--verify-facts", *flags],
                    env=environment, check=True)
            release = Path(temporary) / f"{name}-release"
            subprocess.run([seed, "build", ROOT / f"selfhost/components/{source}/main.my",
                "--release", "--verify-facts", "--no-cache", "--cache-dir", temporary,
                "-o", release], env=environment, check=True)
            subprocess.run([sys.executable, oracle, "--component", release],
                env=environment, check=True)
        manifest = json.loads((args.component_dir / f"{name}.json").read_text())
        subprocess.run([sys.executable, oracle,
            "--component", args.component_dir / manifest["artifact"]], env=environment, check=True)



if __name__ == "__main__":
    main()
