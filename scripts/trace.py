#!/usr/bin/env python3
"""Trace original requests through checked symbols and source-pinned test evidence."""
import argparse
import json
import sys
from pathlib import Path
import tempfile

from intent import model
from intent.report import snapshot, attach, query
from verification import core
from verification.scheduler import add_arguments, executor_from_args


def verify(compiler, entry, filename, verification, cache, previous=None, executor=None):
    report, basis = snapshot(compiler, entry, filename, verification, previous)
    if any(d["severity"] == "error" for d in report["diagnostics"]):
        raise ValueError("resolve traceability diagnostics before verification")
    # Execute a captured project. All source and intent bytes are explicit inputs,
    # so undeclared requirements cannot accidentally inherit a successful verdict.
    with tempfile.TemporaryDirectory(prefix="intent-capture-") as temporary:
        captured = Path(temporary) / "project"
        core.capture_tree(entry.parent, captured, basis["project"])
        if core.tree(captured) != basis["project"]:
            raise ValueError("project changed during intent capture")
        manifest = model.read(captured / verification)
        for step in manifest["steps"]:
            step["inputs"] = sorted(set(step.get("inputs", [])) | set(basis["project"]))
            step["tools"] = sorted(set(step.get("tools", [])) | {str(compiler)})
        core.atomic_json(captured / verification, manifest)
        result = core.run_manifest(captured / verification, cache_dir=cache, executor=executor)
    after, _ = snapshot(compiler, entry, filename, verification, previous)
    if after["basis_sha256"] != report["basis_sha256"]:
        raise ValueError("intent, source or tools changed during verification")
    receipt = {"version": "intent-evidence-v1", "basis_sha256": report["basis_sha256"],
               "verification": result, "runtime_coverage": "not measured"}
    return {"receipt": receipt, "sha256": core.digest(receipt)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("report", "verify"))
    parser.add_argument("entry", type=Path)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--intent", default="intent.json")
    parser.add_argument("--verification", default="verify.json")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--requirement")
    parser.add_argument("--symbol")
    add_arguments(parser)
    args = parser.parse_args()
    entry, compiler = args.entry.resolve(), args.compiler.resolve()
    if args.output and (args.output.resolve() == entry.parent or entry.parent in args.output.resolve().parents):
        raise ValueError("store trace outputs outside the project to preserve snapshot identity")
    previous = model.read(args.previous, 64 * 1024 * 1024) if args.previous else None
    if args.action == "verify":
        if args.cache is None or args.output is None:
            raise ValueError("verify requires --cache and --output")
        if entry.parent == args.cache.resolve() or entry.parent in args.cache.resolve().parents:
            raise ValueError("cache must be outside the project")
        if args.scheduler and (entry.parent == args.scheduler.resolve() or entry.parent in args.scheduler.resolve().parents):
            raise ValueError("scheduler database must be outside the project")
        result = verify(compiler, entry, args.intent, args.verification, args.cache.resolve(), previous,
                        executor=executor_from_args(args))
        passed = result["receipt"]["verification"]["full_manifest_passed"]
    else:
        result, _ = snapshot(compiler, entry, args.intent, args.verification, previous)
        result = attach(result, model.read(args.evidence, 64 * 1024 * 1024) if args.evidence else None)
        result = query(result, args.requirement, args.symbol)
        passed = not any(d["severity"] == "error" for d in result["diagnostics"])
    if args.output:
        core.atomic_json(args.output.resolve(), result)
    else:
        print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(json.dumps({"code": "I_INVALID_TRACE", "message": str(error)}), file=sys.stderr)
        raise SystemExit(2)
