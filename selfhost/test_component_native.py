#!/usr/bin/env python3
"""Qualify pure Selka tests and the installed native protocol boundary."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def require_completed_tests(output):
    """Unsupported has a successful CLI status; qualification still rejects it."""
    report = json.loads(output)
    statuses = ("passed", "cached", "failed", "skipped", "unsupported")
    if report.get("version") != "native-tests-v1" or not isinstance(report.get("tests"), list):
        raise RuntimeError("component tests did not produce a native-tests-v1 report")
    actual = dict.fromkeys(statuses, 0)
    for row in report["tests"]:
        if not isinstance(row, dict) or row.get("status") not in actual:
            raise RuntimeError("component test report contains an unknown verdict")
        actual[row["status"]] += 1
    if any(type(report.get(name)) is not int or report[name] != actual[name] for name in statuses):
        raise RuntimeError("component test report counts disagree with its verdicts")
    if actual["failed"] or actual["unsupported"] or actual["skipped"] or not actual["passed"] + actual["cached"]:
        raise RuntimeError("component qualification requires every selected test to pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", required=True)
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--component-dir", type=Path, required=True)
    parser.add_argument("--owned-compiler-pin", type=Path)
    parser.add_argument("--seed-source", type=Path)
    args = parser.parse_args()
    pin_flags = ["--owned-compiler-pin", args.owned_compiler_pin] if args.owned_compiler_pin else []
    archive_flags = ["--seed-source", args.seed_source] if args.seed_source else []
    guest_flags = ["--experimental-zero-rc"] if args.owned_compiler_pin else []
    output = subprocess.check_output([args.builder, "--root", ROOT,
        "--zig", args.zig, "--seed-only", *pin_flags, *archive_flags], text=True)
    seed = Path(output.strip().splitlines()[-1])
    environment = {name: value for name, value in os.environ.items()
                   if not name.startswith("MYLANG_") and name != "ZIG"}
    environment.update(MYLANG_ZIG=args.zig, MYLANG_CORE_RUNTIME_CACHE="", MYL_CORE_LEAKCHECK="1")
    # The independent source-only compiler has no libexec siblings. These are the
    # already-provisioned artifacts being qualified, never an installed host.
    environment["MYLANG_COMPONENT_DIR"] = str(args.component_dir.resolve())
    installed = {}
    for name in ("test-index", "cache-plan"):
        manifest = json.loads((args.component_dir / f"{name}.json").read_text())
        if args.owned_compiler_pin and manifest.get("memory_mode") != "zero-rc-v1":
            raise RuntimeError(f"{name}: installed component is not qualified with checked ownership")
        artifact = manifest["artifact"]
        if not isinstance(artifact, str) or Path(artifact).name != artifact:
            raise RuntimeError(f"{name}: manifest artifact must name one installed file")
        installed[name] = args.component_dir / artifact
        with installed[name].open("rb") as source:
            actual = hashlib.file_digest(source, "sha256").hexdigest()
        if actual != manifest.get("sha256"):
            raise RuntimeError(f"{name}: installed component digest differs from manifest")
    for source, name in (("test_index", "test-index"), ("cache_plan", "cache-plan")):
        oracle = ROOT / f"selfhost/tests/run_{source}_component.py"
        with tempfile.TemporaryDirectory(prefix="selka-component-tests-") as temporary:
            for flags in ([], ["--release"]):
                output = subprocess.check_output([seed, "test", ROOT / f"selfhost/components/{source}/tests.my",
                    "--json", "--no-cache", "--cache-dir", temporary, "--verify-facts", *flags, *guest_flags],
                    env=environment, text=True)
                print(output, end="")
                require_completed_tests(output)
            release = Path(temporary) / f"{name}-release"
            subprocess.run([seed, "build", ROOT / f"selfhost/components/{source}/main.my",
                "--release", "--verify-facts", "--no-cache", "--cache-dir", temporary,
                "-o", release, *guest_flags], env=environment, check=True)
            subprocess.run([sys.executable, oracle, "--component", release],
                env=environment, check=True)
        subprocess.run([sys.executable, oracle,
            "--component", installed[name]], env=environment, check=True)



if __name__ == "__main__":
    main()
