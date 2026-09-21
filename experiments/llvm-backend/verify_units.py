#!/usr/bin/env python3
"""Check that every unit of a manifest translates, assembles and type-checks.

    verify_units.py MANIFEST.json [MANIFEST.json ...] [--stop]

For each emitted unit this parses the QBE IL, builds SSA, emits LLVM IR, and runs
the pinned `zig cc` over the result, so a unit is reported only when the whole
path works.  A failure prints the unit, the construct and the compiler's own
diagnostic.  The exit status is non-zero when any unit fails.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True

import qbe_llvm  # noqa: E402


def check(manifest_path, stop_on_failure=False, keep=None):
    """Translate and assemble every unit of one manifest."""
    with open(manifest_path) as handle:
        manifest = json.load(handle)
    signatures = {f["name"]: qbe_llvm.signature_map(qbe_llvm.parse_unit(f["il"], f["name"]))
                  for f in manifest["functions"]}
    failures = []
    with tempfile.TemporaryDirectory() as work:
        for index, unit in enumerate(manifest["functions"]):
            name = unit["name"]
            try:
                ir = qbe_llvm.translate_text(unit["il"], name, signatures)
            except qbe_llvm.ParseError as error:
                failures.append((name, "translate", str(error)))
                if stop_on_failure:
                    break
                continue
            except Exception as error:  # noqa: BLE001 - report anything unexpected
                failures.append((name, "translate", f"{type(error).__name__}: {error}"))
                if stop_on_failure:
                    break
                continue
            if keep:
                with open(f"{keep}.{index}.ll", "w") as handle:
                    handle.write(ir)
            path = os.path.join(work, "unit.ll")
            with open(path, "w") as handle:
                handle.write(ir)
            done = subprocess.run(
                ["zig", "cc", "-S", "-O2", "-fPIC", "-g0", path, "-o",
                 os.path.join(work, "unit.s")], capture_output=True, text=True)
            if done.returncode != 0:
                failures.append((name, "llvm", done.stderr.strip()))
                if stop_on_failure:
                    break
    return manifest, failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifests", nargs="+")
    parser.add_argument("--stop", action="store_true",
                        help="stop at the first failing unit")
    parser.add_argument("--keep", help="write each translated unit to KEEP.N.ll")
    options = parser.parse_args()
    total = 0
    failed = 0
    for path in options.manifests:
        manifest, failures = check(path, options.stop, options.keep)
        total += len(manifest["functions"])
        failed += len(failures)
        status = "OK" if not failures else f"{len(failures)} FAILED"
        print(f"{path}: {len(manifest['functions'])} units, {status}")
        for name, stage, detail in failures[:10]:
            first = detail.split("\n")[0]
            print(f"  [{stage}] {name}: {first}")
            for line in detail.split("\n")[1:4]:
                print(f"        {line}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
