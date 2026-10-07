#!/usr/bin/env python3
"""Fifty strict S4-M cases of all nine inherited kinds, with retained sources.

Launch the entire command under core-qualification.lock so the old gate and
this matrix cannot overlap. Each worker also obtains a normal build slot.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "experiments/new-core-s3-20261006/wave-x/integration/fuzz_qualification.py"
KINDS = ("s0", "s1", "rc", "rebinding", "iteration", "dict", "text", "number", "functions")
HARNESSES = {
    "text": ROOT / "experiments/new-core-s3-20261006/wave-c/s3-char/fuzz_char.py",
    "number": ROOT / "experiments/new-core-s2-20261005/wave-b/s2-t2/fuzz_number.py",
}


def git(*argv):
    return subprocess.check_output(["git", *argv], cwd=ROOT, text=True).strip()


def identity(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--jobs", type=int, choices=(1, 2, 3), default=3)
    args = parser.parse_args()
    if git("status", "--porcelain", "--untracked-files=no"):
        parser.error("tracked files must be clean for the whole matrix")
    args.evidence, args.cache = args.evidence.resolve(), args.cache.resolve()
    if args.evidence.exists() or args.cache.exists():
        parser.error("fresh evidence and cache paths are required")
    oracles = {"old": identity(args.old.resolve()), "new": identity(args.core.resolve())}
    commit = git("rev-parse", "HEAD")
    args.evidence.mkdir(parents=True)
    args.cache.mkdir(parents=True)
    manifest = {"source_commit": commit, "oracles": oracles, "cases_per_kind": 50,
                "kinds": list(KINDS), "jobs": args.jobs}
    (args.evidence / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    def run(kind):
        command = [str(ROOT / "scripts/build-slot.sh"), "build", "--", "nice", "-n", "10",
                   sys.executable, str(WRAPPER), "--kind", kind, "--cases", "50",
                   "--seed", str(4401 + KINDS.index(kind)),
                   "--old", oracles["old"]["path"], "--new", oracles["new"]["path"],
                   "--evidence", str(args.evidence / kind), "--cache-root", str(args.cache / kind)]
        if kind in HARNESSES:
            command.extend(["--harness", str(HARNESSES[kind])])
        with (args.evidence / f"{kind}.log").open("x") as stream:
            stream.write(f"source_commit={commit}\n$ {shlex.join(command)}\n")
            stream.flush()
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            stream.write(f"\nexit={result.returncode}\n")
        path = args.evidence / kind / "summary.json"
        summary = json.loads(path.read_text()) if path.exists() else {"missing_summary": True}
        passed = (result.returncode == 0 and summary.get("qualified") is True
                  and summary.get("accepted") == 50 and summary.get("cases_requested") == 50
                  and summary.get("oracles") == oracles)
        print(f"{kind}: {'PASS' if passed else 'STOP'}; {summary.get('elapsed_seconds', '?')}s", flush=True)
        return kind, {"passed": passed, "summary": summary}

    order = ("number",) + tuple(kind for kind in KINDS if kind != "number")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as workers:
        results = dict(workers.map(run, order))
    unchanged = git("rev-parse", "HEAD") == commit and not git("status", "--porcelain", "--untracked-files=no")
    same_oracles = all(identity(Path(item["path"])) == item for item in oracles.values())
    summary = {**manifest, "source_unchanged": unchanged, "oracles_unchanged": same_oracles,
               "results": results, "qualified": unchanged and same_oracles and all(item["passed"] for item in results.values())}
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
