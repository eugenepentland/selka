#!/usr/bin/env python3
"""Single authority for the pinned stage-0 compiler.

Every selfhost differential harness must resolve its stage-0 compiler through
this module.  The recorded pin in ``selfhost/stage0-pin.json`` names a
content-addressed artifact living in a *shared* cache (by default
``~/.cache/mylang/stage0/<sha256>/mylang``).  ``require()`` resolves that path,
verifies its sha256 against the pin, and only then hands the path to a harness.

Content addressing is what makes the artifact immutable: a rebuild that changes
the binary produces a new sha256 and therefore a new path.  An existing
artifact is never overwritten with different bytes, and the pin must be
re-recorded explicitly with ``selfhost/tools/pin-stage0.sh`` before a harness
will use a new binary.

Set ``MYLANG_STAGE0_CACHE`` to relocate the shared cache (for example, a build
farm with a read-only home).  The pin records the default cache directory and
the override variable so a mismatch is always reported instead of silently
falling back to the unpinned ``zig-out/bin/mylang``.
"""
from __future__ import annotations

import hashlib
import json
import os
import threading
from pathlib import Path
from typing import List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
PIN_PATH = ROOT / "selfhost" / "stage0-pin.json"
CACHE_ENV = "MYLANG_STAGE0_CACHE"
DEFAULT_CACHE_DIR = Path.home() / ".cache" / "mylang" / "stage0"
ARTIFACT_NAME = "mylang"
BUILD_HINT = (
    "run selfhost/tools/build-stage0.sh to (re)build the artifact, then "
    "selfhost/tools/pin-stage0.sh to record the new sha256"
)

# Verification is cheap for one process but not free; memoize the successful
# path so a harness that spawns hundreds of compiler invocations hashes the
# artifact once.
_lock = threading.Lock()
_cached: Optional[Path] = None


class PinError(RuntimeError):
    """The stage-0 pin cannot be satisfied; the message is actionable."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_pin(pin_path: Optional[Path] = None) -> dict:
    """Load and sanity-check ``selfhost/stage0-pin.json``."""
    path = Path(pin_path) if pin_path is not None else PIN_PATH
    if not path.is_file():
        raise PinError("stage0 pin: missing {}; {}".format(path, BUILD_HINT))
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PinError("stage0 pin: cannot read {}: {}; {}".format(path, error, BUILD_HINT))
    if not isinstance(data, dict):
        raise PinError("stage0 pin: {} must contain a JSON object; {}".format(path, BUILD_HINT))
    sha = data.get("sha256")
    if not isinstance(sha, str) or not sha:
        raise PinError("stage0 pin: {} does not record a sha256; {}".format(path, BUILD_HINT))
    return data


def cache_root(pin: Optional[dict] = None) -> Path:
    """Return the shared artifact cache directory.

    ``MYLANG_STAGE0_CACHE`` wins over the path recorded in the pin; the pin's
    ``cache_dir`` is the default so every worktree resolves the same artifact.
    """
    override = os.environ.get(CACHE_ENV)
    if override:
        return Path(override).expanduser()
    pin = pin if pin is not None else load_pin()
    recorded = pin.get("cache_env")
    if recorded and recorded != CACHE_ENV:
        override = os.environ.get(recorded)
        if override:
            return Path(override).expanduser()
    cache_dir = pin.get("cache_dir")
    if isinstance(cache_dir, str) and cache_dir:
        return Path(cache_dir).expanduser()
    artifact = pin.get("artifact")
    if isinstance(artifact, str) and artifact:
        return Path(artifact).expanduser().parent.parent
    return DEFAULT_CACHE_DIR


def artifact_path(pin: Optional[dict] = None) -> Path:
    """Resolve the content-addressed artifact for the recorded sha256."""
    pin = pin if pin is not None else load_pin()
    return cache_root(pin) / pin["sha256"] / ARTIFACT_NAME


def verify(path, pin: Optional[dict] = None) -> Tuple[bool, str]:
    """Verify one candidate artifact against the pin.

    Returns ``(ok, detail)``.  ``detail`` is an actionable message when the
    file is missing, unreadable, or its sha256 differs from the pin.
    """
    try:
        pin = pin if pin is not None else load_pin()
    except PinError as error:
        return False, str(error)
    candidate = Path(path)
    expected = pin.get("sha256")
    if not candidate.is_file():
        return False, (
            "stage0 artifact: missing {path} (pin records sha256 {sha}); {hint}".format(
                path=candidate, sha=expected, hint=BUILD_HINT
            )
        )
    try:
        actual = _sha256(candidate)
    except OSError as error:
        return False, (
            "stage0 artifact: cannot hash {path}: {error}; {hint}".format(
                path=candidate, error=error, hint=BUILD_HINT
            )
        )
    if actual != expected:
        return False, (
            "stage0 artifact: hash mismatch for {path}: pin records {expected} but the "
            "artifact is {actual}; {hint}".format(
                path=candidate, expected=expected, actual=actual, hint=BUILD_HINT
            )
        )
    return True, ""


def verify_tools(artifact: Path, pin: Optional[dict] = None) -> List[str]:
    """Verify any auxiliary tools recorded in the pin (for example ``qbe``).

    ``mylang`` looks for ``qbe`` beside itself before falling back to ``PATH``;
    the cache directory therefore carries the exact tool the pin recorded.  A
    pin without a ``tools`` map stays compatible and is not checked further.
    """
    try:
        pin = pin if pin is not None else load_pin()
    except PinError as error:
        return [str(error)]
    tools = pin.get("tools")
    if not isinstance(tools, dict):
        return []
    problems = []
    for name, expected in sorted(tools.items()):
        if not isinstance(expected, str) or not expected:
            continue
        candidate = artifact.parent / name
        if not candidate.is_file():
            problems.append(
                "stage0 tool: missing {path} (pin records sha256 {sha}); {hint}".format(
                    path=candidate, sha=expected, hint=BUILD_HINT
                )
            )
            continue
        try:
            actual = _sha256(candidate)
        except OSError as error:
            problems.append(
                "stage0 tool: cannot hash {path}: {error}; {hint}".format(
                    path=candidate, error=error, hint=BUILD_HINT
                )
            )
            continue
        if actual != expected:
            problems.append(
                "stage0 tool: hash mismatch for {path}: pin records {expected} but the "
                "tool is {actual}; {hint}".format(
                    path=candidate, expected=expected, actual=actual, hint=BUILD_HINT
                )
            )
    return problems


def diagnostics(pin: Optional[dict] = None) -> Tuple[Optional[Path], List[str]]:
    """Return ``(resolved_path, problems)`` for the current pin state."""
    try:
        pin = pin if pin is not None else load_pin()
    except PinError as error:
        return None, [str(error)]
    path = artifact_path(pin)
    ok, detail = verify(path, pin)
    problems = [] if ok else [detail]
    if ok:
        problems.extend(verify_tools(path, pin))
    return path, problems


def require() -> Path:
    """Return the verified pinned artifact path, or raise :class:`PinError`.

    This never falls back to ``zig-out/bin/mylang``: an unpinned binary is not a
    stage-0 oracle.
    """
    global _cached
    with _lock:
        if _cached is not None:
            return _cached
        path, problems = diagnostics()
        if problems:
            raise PinError("\n".join(problems))
        _cached = path
        return path


def reset_cache() -> None:
    """Drop the memoized verification (used by the gate self-check)."""
    global _cached
    with _lock:
        _cached = None


def main(argv: Optional[List[str]] = None) -> int:
    import sys

    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] == "--diagnostics":
        path, problems = diagnostics()
        if path is not None:
            print("stage0 artifact: {}".format(path))
        for problem in problems:
            print("stage0 pin problem: {}".format(problem))
        return 1 if problems else 0
    try:
        print(require())
    except PinError as error:
        print("stage0 pin: {}".format(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
