#!/usr/bin/env python3
"""Freeze a cohort manifest with the identities that make its numbers comparable.

    python3 experiments/diagnostic-feedback/freeze.py --cohort m1-pilot --split dev --repetitions 1
    python3 experiments/diagnostic-feedback/freeze.py --cohort m1 --split test --repetitions 2
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1] / "experiments" / "cascade"))
import cohort  # noqa: E402
import conditions  # noqa: E402
import run as cascade_run  # noqa: E402 — the cascade runner owns the toolchain identity
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("dfrun", HERE / "run.py")
dfrun = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dfrun)

ARMS = ("text", "text_fix", "json", "json_fix")


def corpus_sha256(split: str) -> str:
    """A hash of every case source in the split: a revised task is a new cohort."""
    digest = hashlib.sha256()
    for path in sorted((HERE / "cases" / split).rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(HERE).as_posix().encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()[:16]


def identity(split: str) -> dict:
    settings = Path.home() / ".dsh" / "settings.yaml"
    model, effort = "deepseek-v4-flash", "max"
    if settings.is_file():
        for line in settings.read_text().splitlines():
            if "model:" in line:
                model = line.split("model:", 1)[1].strip()
            if "reasoningEffort:" in line:
                effort = line.split("reasoningEffort:", 1)[1].strip()
    return {
        "compiler_sha256": cascade_run.toolchain()["compiler_sha256"],
        "wrapper_schema": "wrapper-v2-events",
        "prompt_sha256": hashlib.sha256(dfrun.PROMPT.encode()).hexdigest()[:16],
        "remedy_sha256": hashlib.sha256(json.dumps(conditions.REMEDIES, sort_keys=True).encode()).hexdigest()[:16],
        "model": model,
        "reasoning_effort": effort,
        "invocation_limit": dfrun.INVOCATION_LIMIT,
        "session_deadline_s": 900,
        "cache_policy": "ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR per attempt inside the working copy",
        "corpus_sha256": corpus_sha256(split),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", required=True)
    parser.add_argument("--split", default="test", choices=("dev", "test"))
    parser.add_argument("--repetitions", type=int, default=2)
    parser.add_argument("--seed", type=int, default=20260919)
    parser.add_argument("--purpose", default="M1 factorial")
    args = parser.parse_args()
    cases = sorted(path.name for path in (HERE / "cases" / args.split).iterdir() if (path / "project").is_dir())
    manifest = cohort.new_manifest(args.cohort, cases, list(ARMS), args.repetitions, identity(args.split),
                                   args.seed, args.purpose)
    path = cohort.save(manifest, HERE / "cohorts" / args.cohort / "manifest.json")
    print(f"{args.cohort}: {len(cases)} cases x {len(ARMS)} arms x {args.repetitions} repetitions "
          f"= {len(manifest['schedule'])} cells")
    print(f"identity: model={manifest['identity']['model']}/{manifest['identity']['reasoning_effort']} "
          f"compiler={manifest['identity']['compiler_sha256'][:12]} remedy={manifest['identity']['remedy_sha256']}")
    print(f"manifest: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
