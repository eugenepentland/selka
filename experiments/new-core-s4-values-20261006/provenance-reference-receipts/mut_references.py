#!/usr/bin/env python3
"""Retain old/S3/V/E frame identity for small consuming mutation helpers."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from trace_units import ROOT, command

CASES = {
    "bounds": ("2", "    return xs[x]\n"),
    "assert": ("1", "    assert x == 0, \"mut check\"\n    return x\n"),
    "overflow": ("9223372036854775807", "    if x < 0:\n        return 0\n    return x + 1\n"),
}


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
    report = {"complete": False, "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "compilers": {name: identity(path) for name, path in compilers.items()}, "comparisons": []}
    try:
        for case, (argument, body) in CASES.items():
            source = area / case
            source.mkdir()
            (source / "app.my").write_text("module app\nimport leaf\ndef main() -> int:\n    xs = [1]\n" + f"    return leaf.origin(mut xs, {argument})\n")
            (source / "leaf.my").write_text("module leaf\npublic def origin(xs: mut list[int], x: int) -> int:\n    xs.append(2)\n" + body)
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
                report["comparisons"].append({"case": case, "mode": mode,
                    "differences": [name for name in ("s3", "values", "new") if outputs[name] != outputs["old"]], "outputs": outputs})
                print(case, mode, {name: "leaf::origin" in result["stderr"] for name, result in outputs.items()}, flush=True)
        for name, path in compilers.items():
            if identity(path) != report["compilers"][name]:
                raise ValueError(f"compiler changed: {name}")
        report["complete"] = True
    finally:
        (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
