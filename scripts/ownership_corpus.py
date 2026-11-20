#!/usr/bin/env python3
"""Which compiler, and which suite inputs, wrote a directory of ownership certificates.

The `ownership-proof` gate action (`scripts/ownership_proof.py`) checks the certificates that `selka test SUITE
--emit-certificates DIR` leaves under `.selka-cache/ownership-certificates/SUITE/MODE`. `selka test` writes a program's
certificates only when it builds the program, and a test served from a receipt (its own, a tier of reuse across compiler edits,
or one another worktree published to the per-user store) builds nothing. So the directory holds what the last run that built the
programs left there: after an edit and its revert it can hold the certificates of the edit, and in a fresh worktree whose tests
all hit shared receipts it can hold almost nothing.

A directory therefore carries a stamp, `stamp.json`: the identity of the compiler (`selka validate-certificates --identity`)
and a digest of the suite's inputs that wrote it. The stamp is written only after a complete run, by `scripts/test_lang.py`,
which also refuses to trust a directory whose stamp is not the current one: it deletes the directory and rebuilds every program
with `--force`, so a receipt cannot stand in for the build. `ownership_proof.py` checks the stamps again before it reads the
directories, and regenerates a stale one by running the same wrapper.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ".selka-cache/ownership-certificates"
STAMP = "stamp.json"
STAMP_VERSION = 1
# The language suites the gate runs (`LangSuite` in build.zig) and the work cache each keeps.
SUITES = {
    "tests/lang": ".selka-cache/lang-tests",
    "tests/value_semantics": ".selka-cache/value-semantics-tests",
    "tests/ported": ".selka-cache/ported-tests",
}


class CorpusError(RuntimeError):
    """The compiler cannot name itself, or a certificate directory cannot be regenerated."""


class Recipe(NamedTuple):
    """One `selka test` run of the language gate that writes certificates, exactly as build.zig starts it."""
    suite: str
    mode: str
    directory: str
    arguments: tuple[str, ...]
    environment: dict


# The gate's language runs check their programs with the leak check on (`SELKA_CORE_LEAKCHECK=1`), and the debug run also
# verifies the facts it relies on (`--verify-facts`). Release builds are not part of the gate (`-Dtest-release=true` adds them).
LEAK_CHECK = {"SELKA_CORE_LEAKCHECK": "1"}
# The release run's certificate directory, which a gate without `-Dtest-release=true` must not keep (see `retire`).
RETIRED_MODE = "release"


def recipes(release: bool = False) -> list[Recipe]:
    """The runs that write the corpus, exactly as build.zig starts them: a debug run of each suite, and with `release`
    (`-Dtest-release=true`) its release run as well."""
    found = []
    for suite, cache in SUITES.items():
        debug = f"{CORPUS}/{suite}/debug"
        found.append(Recipe(suite, "debug", debug, ("--verify-facts", "--cache-dir", cache, "--emit-certificates", debug), LEAK_CHECK))
        if release:
            directory = f"{CORPUS}/{suite}/{RETIRED_MODE}"
            found.append(Recipe(suite, RETIRED_MODE, directory,
                                ("--release", "--verify-facts", "--cache-dir", cache + "-release", "--emit-certificates", directory),
                                LEAK_CHECK))
    return found


def retire(root: Path = ROOT) -> list[str]:
    """Remove the release certificate directories of a gate that does not run release builds. The proof reads every
    certificate under the corpus, so a directory left by an earlier `-Dtest-release=true` run would be checked as if this gate
    wrote it. Returns the directories it removed."""
    gone = []
    for suite in SUITES:
        directory = root / CORPUS / suite / RETIRED_MODE
        if directory.exists():
            shutil.rmtree(directory, ignore_errors=True)
            gone.append(directory.relative_to(root).as_posix())
    return gone


def compiler_identity(compiler: str, run=subprocess.run) -> str:
    """The compiler's own identity: the digest of its sources, Zig version and mode (not of its executable's bytes, which
    change with a comment under a Debug build)."""
    done = run([compiler, "validate-certificates", "--identity"], capture_output=True, text=True, errors="replace")
    identity = done.stdout.strip()
    if done.returncode != 0 or len(identity) != 64 or any(c not in "0123456789abcdef" for c in identity):
        raise CorpusError(f"cannot read the compiler identity from `{compiler} validate-certificates --identity`: {(done.stdout + done.stderr)[-300:]}")
    return identity


def inputs_digest(root: Path, suite: str) -> str:
    """Digest of every file of a suite, by relative path and bytes: what its programs are made from, besides the compiler."""
    hash = hashlib.sha256()
    base = root / suite
    for path in sorted(p for p in base.rglob("*") if p.is_file() and "__pycache__" not in p.parts):
        hash.update(path.relative_to(base).as_posix().encode() + b"\0")
        hash.update(hashlib.sha256(path.read_bytes()).digest())
    return hash.hexdigest()


def current_key(compiler: str, root: Path, suite: str, run=subprocess.run) -> dict:
    """The stamp a directory written by `compiler` from `suite` as it is now must carry."""
    return {"version": STAMP_VERSION, "compiler": compiler_identity(compiler, run), "inputs": inputs_digest(root, suite)}


def read_stamp(directory: Path) -> dict | None:
    try:
        value = json.loads((directory / STAMP).read_text())
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def is_fresh(directory: Path, key: dict) -> bool:
    """Whether `directory` was completely written for `key`."""
    return read_stamp(directory) == key


def begin(directory: Path, key: dict) -> bool:
    """Start a run that writes into `directory`. Returns True when the run must rebuild every program (`--force`): the stamp is
    not `key`, so nothing in the directory is trusted and it is emptied. The stamp is gone until `commit`, so a run that dies
    leaves a directory that claims nothing."""
    if is_fresh(directory, key):
        return False
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir(parents=True, exist_ok=True)
    return True


def commit(directory: Path, key: dict) -> None:
    """Stamp `directory` as completely written for `key`."""
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / (STAMP + ".tmp")
    temporary.write_text(json.dumps(key, sort_keys=True, separators=(",", ":")))
    os.replace(temporary, directory / STAMP)


def wrapper_command(recipe: Recipe, compiler: str) -> list[str]:
    """The language gate's own wrapper, started as build.zig starts it."""
    return [sys.executable, "scripts/test_lang.py", "--compiler", compiler, "--allowlist", "tests/unsupported.json", recipe.suite, *recipe.arguments]


def stale(compiler: str, root: Path = ROOT, run=subprocess.run, release: bool = False) -> list[Recipe]:
    """The recipes whose certificate directory is not stamped for the compiler and the suite as they are now."""
    keys = {}
    found = []
    for recipe in recipes(release):
        if recipe.suite not in keys:
            keys[recipe.suite] = current_key(compiler, root, recipe.suite, run)
        if not is_fresh(root / recipe.directory, keys[recipe.suite]):
            found.append(recipe)
    return found


def regenerate(compiler: str, root: Path = ROOT, jobs: int = 6, run=subprocess.run, release: bool = False) -> list[str]:
    """Rewrite every stale certificate directory by running the gate's wrapper for its recipe (the wrapper empties the directory
    and rebuilds every program, then stamps it). Returns the directories it rewrote; raises when a run fails."""
    todo = stale(compiler, root, run, release)
    if not todo:
        return []

    def one(recipe: Recipe) -> tuple[Recipe, subprocess.CompletedProcess]:
        env = dict(os.environ, **recipe.environment)
        return recipe, run(wrapper_command(recipe, compiler), cwd=root, env=env, capture_output=True, text=True, errors="replace")

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(jobs, len(todo)))) as pool:
        results = list(pool.map(one, todo))
    failed = [(recipe, done) for recipe, done in results if done.returncode != 0]
    if failed:
        recipe, done = failed[0]
        raise CorpusError(f"cannot regenerate the certificates of {recipe.suite} ({recipe.mode}): `scripts/test_lang.py` exited "
                          f"{done.returncode}: {(done.stderr or done.stdout)[-600:]}")
    return [recipe.directory for recipe in todo]
