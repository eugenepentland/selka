#!/usr/bin/env python3
"""Require old/E leaf-trap parity and explicitly retain inherited S3/V differences."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from trace_units import ROOT, command


def identity(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("old", "s3", "values", "new"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(ROOT / "experiments")
    area.mkdir(parents=True, exist_ok=False)
    cache = ROOT / ".mylang-cache/s4-emission" / area.name
    cache.mkdir(parents=True, exist_ok=False)
    compilers = {name: getattr(args, name).resolve() for name in ("old", "s3", "values", "new")}
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report = {"qualified": False, "source_commit": head,
              "compilers": {name: identity(path) for name, path in compilers.items()}, "comparisons": []}
    try:
        for case in ("bounds", "overflow"):
            source = area / case
            source.mkdir()
            for path in (ROOT / "experiments/new-core-s4-emission-20261006/leaf-trap-provenance-reducer" / case).glob("*.my"):
                (source / path.name).write_bytes(path.read_bytes())
            for mode in ("debug", "release"):
                outputs = {}
                for name, compiler in compilers.items():
                    stem = f"{case}-{mode}-{name}"
                    native = cache / stem
                    native.mkdir()
                    argv = [compiler, "build", source / "app.my", "--cache-dir", native / "cache", "-o", native / "program"]
                    if mode == "release":
                        argv.append("--release")
                    command(argv, area / f"build-{stem}.json")
                    result = command([native / "program"], area / f"run-{stem}.json", 1)
                    outputs[name] = {key: result[key] for key in ("status", "stdout", "stderr")}
                if outputs["old"] != outputs["new"]:
                    raise ValueError(f"old/E leaf diagnostics differ: {case}/{mode}")
                if "leak:" in outputs["new"]["stderr"]:
                    raise ValueError(f"leaf diagnostics leaked: {case}/{mode}")
                report["comparisons"].append({"case": case, "mode": mode, "old_new_identical": True,
                    "inherited_differences": [name for name in ("s3", "values") if outputs[name] != outputs["old"]],
                    "outputs": outputs})
                print(f"{case}/{mode}: exact old/E; inherited differences explicitly retained", flush=True)
        if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() != head:
            raise ValueError("source checkpoint changed")
        for name, path in compilers.items():
            if identity(path) != report["compilers"][name]:
                raise ValueError(f"compiler changed: {name}")
        report["qualified"] = True
    finally:
        (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
