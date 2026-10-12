#!/usr/bin/env python3
"""Prepare real compiler/check and forced test-driver workloads for native Juice.

Generation does not acquire admission or run measurements. The suites stay fresh:
an external compiler's complete producer/provider closure is not qualified here.
"""
import argparse
import json
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compiler, zig = args.compiler.resolve(strict=True), args.zig.resolve(strict=True)
    output = args.output.absolute()
    output.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent
    for name in ("cases.my", "oracle.py"):
        shutil.copyfile(here / name, output / name)
    workloads = [
        {"name": "compiler-check", "family": "compiler-check", "unit": "checked fixture", "units": 1,
         "args": ["check", "{root}/cases.my", "--no-cache"], "expected_stdout": "", "timeout_seconds": 30},
        {"name": "forced-test-driver", "family": "guest-test-driver", "unit": "fresh passing guest test", "units": 2,
         "args": ["test", "{root}/cases.my", "--force", "--json", "--cache-dir", "{work}/guest-cache"],
         "stdout_regex": '(?:.|\\n)*("passed":2,"failed":0,"skipped":0,"cached":0,"unsupported":0)(?:.|\\n)*',
         "expected_stdout": '"passed":2,"failed":0,"skipped":0,"cached":0,"unsupported":0',
         "check": ["python3", "{root}/oracle.py", "{stdout}"], "timeout_seconds": 120}]
    components = compiler.parent.parent / "libexec/mylang/components"
    environment = {"MYLANG_ZIG": str(zig), "ZIG": str(zig)}
    dependencies = [str(compiler), str(zig), str(zig.parent / "lib")]
    if components.is_dir():
        environment["MYLANG_COMPONENT_DIR"] = str(components)
        dependencies.append(str(components))
    manifest = {"version": 1, "name": "development-loop-compiler-driver", "adapter": "native",
                "sources": ["cases.my", "oracle.py"], "environment": environment,
                "build": {"compiler": str(compiler), "command": ["cp", "{compiler}", "{binary}"],
                          "tools": ["cp", "python3"], "dependencies": dependencies, "timeout_seconds": 30},
                "workloads": workloads}
    (output / "juice.json").write_text(json.dumps(manifest, indent=2) + "\n")
    suite = {"version": "juice-suite-v1", "workloads": [
        {"id": work["name"], "manifest": "juice.json", "workload": work["name"],
         "complete": False, "reuse": "fresh"} for work in workloads]}
    (output / "suite.json").write_text(json.dumps(suite, indent=2) + "\n")
    print(output / "suite.json")


if __name__ == "__main__":
    main()
