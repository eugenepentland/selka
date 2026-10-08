#!/usr/bin/env python3
"""S5's strict nine-kind fuzz matrix against the frozen old-core references.

S3-X's fuzz_matrix.py unchanged except: the old core is answered from
references/fuzz-v1.json.gz by tools/fuzz_frozen.py (S5-D2), `--references`
replaces `--old`, and `--cases` (default 200; 50 per package) sets the cases per
kind. Every worker obtains a build slot; the parent needs no gate slot. This driver
never builds the compiler or runs gates.
"""
import argparse
import concurrent.futures
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
KINDS = ("s0", "s1", "rc", "rebinding", "iteration", "dict", "text", "number", "functions")
# Float-runtime builds are the longest package sweep. Start that worker first;
# keep the registry and its per-kind seeds fixed so scheduling changes no cases.
EXECUTION_ORDER = ("number",) + tuple(kind for kind in KINDS if kind != "number")
S3 = ROOT / "experiments/new-core-s3-20261006/wave-x/integration"
STUB = HERE / "frozen-old-core"
TEXT_HARNESS = ROOT / "experiments/new-core-s3-20261006/wave-c/s3-char/fuzz_char.py"
NUMBER_HARNESS = ROOT / "experiments/new-core-s2-20261005/wave-b/s2-t2/fuzz_number.py"


def identity(path):
    path = path.resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"oracle must be an executable file: {path}")
    with path.open("rb") as binary:
        return {"path": str(path), "sha256": hashlib.file_digest(binary, "sha256").hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--references", type=Path, required=True, help="Frozen old-core outcomes (references/fuzz-v1.json.gz)")
    parser.add_argument("--cases", type=int, default=200, help="Cases per kind: 50 per package, 200 at S5-X")
    parser.add_argument("--new", type=Path, required=True, help="Explicit qualified final integrated new oracle")
    parser.add_argument("--qualified-head", help="Require this full qualified source commit to remain HEAD")
    parser.add_argument("--evidence", type=Path, help="Fresh directory below experiments; default is a unique UTC/UUID run")
    parser.add_argument("--jobs", type=int, choices=(1, 2, 3), default=3)
    args = parser.parse_args()
    try:
        oracles = {"old": identity(STUB), "new": identity(args.new)}
        if os.path.samefile(STUB, args.new):
            raise ValueError("--old and --new must name distinct oracle files")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if args.qualified_head and args.qualified_head != commit:
        parser.error("--qualified-head must be the full current HEAD commit")
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, text=True):
        parser.error("tracked source must be clean before the final matrix")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:12]
    area = (args.evidence or HERE / f"fuzz-{args.cases}-{run_id}").resolve()
    if not area.is_relative_to(ROOT / "experiments"):
        parser.error("evidence must be below this worktree's experiments directory")
    if area.exists():
        parser.error("evidence directory already exists; retain it and choose a fresh directory")
    cache = ROOT / ".mylang-cache/s5/fuzz" / run_id
    references = {"path": str(args.references.resolve()), "sha256": hashlib.sha256(args.references.read_bytes()).hexdigest()}
    area.mkdir(parents=True)
    print(f"evidence={area}\nsource_commit={commit}", flush=True)
    manifest = {"source_commit": commit, "qualified_head_requested": args.qualified_head,
                "oracles": oracles, "references": references, "cases_per_kind": args.cases, "maximum_parallel_jobs": args.jobs,
                "kinds": list(KINDS), "execution_order": list(EXECUTION_ORDER),
                "cache_root": str(cache), "run_id": run_id}
    (area / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    def run(kind):
        command = [str(ROOT / "scripts/build-slot.sh"), "build", "--", "nice", "-n", "10",
                   sys.executable, str(HERE / "fuzz_frozen.py"), "--kind", kind, "--references", references["path"],
                   "--cases", str(args.cases), "--seed", str(3301 + KINDS.index(kind)),
                   "--old", oracles["old"]["path"], "--new", oracles["new"]["path"],
                   "--evidence", str(area / kind), "--cache-root", str(cache / kind)]
        if kind in ("text", "number"):
            command += ["--harness", str(TEXT_HARNESS if kind == "text" else NUMBER_HARNESS)]
        with (area / f"{kind}.txt").open("x") as log:
            log.write(f"source_commit={commit}\n$ {shlex.join(command)}\n")
            log.flush()
            try:
                result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
                status = result.returncode
                log.write(f"\nexit={status}\n")
            except OSError as error:
                log.write(f"\nlaunch_error={error}\n")
                return kind, False, {"error": str(error)}
        try:
            summary = json.loads((area / kind / "summary.json").read_text())
        except (OSError, ValueError) as error:
            return kind, False, {"error": str(error), "worker_status": status}
        passed = (status == 0 and summary.get("qualified") is True and summary.get("accepted") == args.cases
                  and summary.get("cases_requested") == args.cases and summary.get("oracles") == oracles)
        print(f"{kind}: {'PASS' if passed else 'STOP'}; {summary.get('elapsed_seconds', '?')}s", flush=True)
        return kind, passed, summary

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        completed = {kind: (passed, summary) for kind, passed, summary in pool.map(run, EXECUTION_ORDER)}
    results = [(kind, *completed[kind]) for kind in KINDS]
    try:
        oracles_unchanged = all(identity(Path(item["path"])) == item for item in oracles.values())
    except (OSError, ValueError):
        oracles_unchanged = False
    source_unchanged = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() == commit and not subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, text=True)
    report = {**manifest, "source_unchanged": source_unchanged, "oracles_unchanged": oracles_unchanged,
              "complete": len(results) == len(KINDS),
              "qualified": source_unchanged and oracles_unchanged and all(passed for _, passed, _ in results),
              "kinds": {kind: {"passed": passed, "summary": summary} for kind, passed, summary in results}}
    (area / "matrix.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["qualified"]:
        raise SystemExit("STOP: strict matrix failed; inspect retained evidence")


if __name__ == "__main__":
    main()
