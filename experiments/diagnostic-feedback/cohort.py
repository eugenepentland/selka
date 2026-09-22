#!/usr/bin/env python3
"""Immutable cohorts: what was scheduled, what was run, and what may be pooled.

An experiment is a manifest, not a directory listing. The manifest names every
eligible case, arm, repetition and attempt together with the identities that make
the numbers comparable — compiler, wrapper, prompt, model, remedy set, limits and
cache policy. Scoring reads the manifest and nothing else, so a follow-up run
cannot change a published result, and two manifests with different identities
cannot be pooled by accident.

Evidence lives at `<root>/<cohort>/runs/<arm>/<case>/<repeat>/<attempt>/`. A
destination that already exists is refused: a retry is a new attempt with a
reason and a link to its predecessor, never an overwrite.
"""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import random
import shutil

SCHEMA = "cohort-manifest-v1"
IDENTITY_FIELDS = ("compiler_sha256", "wrapper_schema", "prompt_sha256", "remedy_sha256",
                   "model", "reasoning_effort", "invocation_limit", "session_deadline_s",
                   "cache_policy")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def new_manifest(cohort_id: str, cases: list[str], arms: list[str], repetitions: int,
                 identity: dict, seed: int, purpose: str = "main") -> dict:
    """A frozen manifest with a randomized block schedule.

    One block is one `(case, repetition)`; the arm order inside a block is
    shuffled, then the blocks themselves are shuffled, so treatment, case and
    time are not confounded.
    """
    generator = random.Random(seed)
    blocks = [{"case": case, "repetition": repetition, "order": []}
              for case in cases for repetition in range(1, repetitions + 1)]
    for block in blocks:
        order = list(arms)
        generator.shuffle(order)
        block["order"] = order
    generator.shuffle(blocks)
    return {
        "schema": SCHEMA,
        "cohort_id": cohort_id,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "purpose": purpose,
        "seed": seed,
        "arms": list(arms),
        "cases": list(cases),
        "repetitions": repetitions,
        "identity": identity,
        "blocks": blocks,
        "schedule": [{"arm": arm, "case": block["case"], "repetition": block["repetition"]}
                     for block in blocks for arm in block["order"]],
    }


def save(manifest: dict, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    return path


def load(path: Path) -> dict:
    manifest = json.loads(path.read_text())
    if manifest.get("schema") != SCHEMA:
        raise SystemExit(f"{path}: not a {SCHEMA} manifest")
    return manifest


def incompatible(left: dict, right: dict) -> list[str]:
    """Identity fields that differ; an empty list means the two can be pooled."""
    return [field for field in IDENTITY_FIELDS
            if left["identity"].get(field) != right["identity"].get(field)]


def scheduled(manifest: dict, arm: str, case: str, repetition: int) -> bool:
    return any(row["arm"] == arm and row["case"] == case and row["repetition"] == repetition
               for row in manifest["schedule"])


def attempt_dir(root: Path, arm: str, case: str, repetition: int, attempt: int) -> Path:
    return root / "runs" / arm / case / str(repetition) / str(attempt)


def reserve(directory: Path) -> None:
    """Create the attempt directory, refusing to reuse an existing one."""
    if directory.exists():
        raise SystemExit(f"attempt directory already exists: {directory} — a retry is a new attempt")
    directory.mkdir(parents=True)


def seal(project: Path, destination: Path) -> str:
    """Copy the candidate's source to an immutable snapshot and hash the inventory."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(project, destination,
                    ignore=shutil.ignore_patterns(".cache", ".mylang-cache", "_verify", "__pycache__"))
    entries = {}
    for path in sorted(destination.rglob("*")):
        if path.is_file():
            entries[path.relative_to(destination).as_posix()] = digest(path)
    return hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
