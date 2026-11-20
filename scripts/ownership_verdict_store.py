#!/usr/bin/env python3
"""The per-user store of `ownership-proof` verdicts (docs/tooling/ownership-certificates.md), shared by every worktree.

A verdict is a pure function of the certificate text of one function and of the checker that judged it, so it is keyed by the
digest of the certificate and the digest of the checker (the validator's sources for the Zig verdict, `proofs/ownership` and the
Lean toolchain for the Lean verdict) and may be used by any worktree and any session of the same user: the second worktree to
reach a function reuses the verdict the first computed instead of running the Lean checker again.

The store is the namespace `ownership-verdicts-v1` inside the verification coordinator's shared root
(`$SELKA_VERIFICATION_SHARED_CACHE`, else `$XDG_CACHE_HOME/selka/verification-shared`, else `~/.cache/selka/verification-shared`;
an empty variable disables sharing, and the gate then keeps the same store in the worktree). It follows the protocol of the
other shared namespaces (docs/tooling/cache-retention.md): a format marker, one immutable checksummed file per verdict published
by atomic rename, a shared process lease held by every reader and writer, an exclusive nonblocking lease for the collector (a
store in use is skipped), least-recently-used collection to a bounded number of entries at most once an hour when a process opens
the store, and a `mismatches.log` line when a published verdict differs from one already stored (the stored one is kept).
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

NAMESPACE = "ownership-verdicts-v1"
FORMAT = {"namespace": NAMESPACE, "version": 1}
DEFAULT_MAX_ENTRIES = 150_000
DEFAULT_INTERVAL_SECONDS = 3600
TOUCH_AFTER_SECONDS = 3600
MARKER = "ESTABLISHED"


class StoreError(RuntimeError):
    """The store is not usable (an unknown format, a root that is not a directory)."""


def shared_root(environ=None) -> Path | None:
    """The verification coordinator's shared root: `$SELKA_VERIFICATION_SHARED_CACHE` (empty disables), else the per-user
    default. None when sharing is off."""
    environ = os.environ if environ is None else environ
    named = environ.get("SELKA_VERIFICATION_SHARED_CACHE")
    if named is not None:
        return Path(named) if named else None
    xdg = environ.get("XDG_CACHE_HOME", "")
    if xdg and os.path.isabs(xdg):
        return Path(xdg) / "selka" / "verification-shared"
    home = environ.get("HOME", "")
    return Path(home) / ".cache" / "selka" / "verification-shared" if home else None


def initialize_host(root: Path) -> None:
    """Make `root` a versioned verification store before a namespace is put in it: the coordinator's store refuses a root that
    holds anything else and has no format marker."""
    import fuzz_campaign_store
    fuzz_campaign_store.Store(root)


def _record(kind: str, checker: str, digest: str, verdict: str) -> bytes:
    check = hashlib.sha256(f"{kind}\0{checker}\0{digest}\0{verdict}".encode()).hexdigest()
    return f"{verdict}\n{check}\n".encode()


def _decode(kind: str, checker: str, digest: str, data: bytes) -> str | None:
    try:
        verdict, check, rest = data.decode().split("\n")
    except (ValueError, UnicodeError):
        return None
    if rest != "" or check != hashlib.sha256(f"{kind}\0{checker}\0{digest}\0{verdict}".encode()).hexdigest():
        return None
    return verdict


class VerdictStore:
    """Verdicts by (kind, checker, certificate digest) under `parent / ownership-verdicts-v1`."""

    def __init__(self, parent: Path, max_entries: int = DEFAULT_MAX_ENTRIES, interval: int = DEFAULT_INTERVAL_SECONDS):
        self.parent = Path(parent)
        self.directory = self.parent / NAMESPACE
        self.max_entries = max_entries
        self.interval = interval
        self.directory.mkdir(parents=True, exist_ok=True)
        marker = self.directory / "format.json"
        if marker.exists():
            try:
                found = json.loads(marker.read_text())
            except (OSError, ValueError):
                found = None
            if found != FORMAT:
                raise StoreError(f"{marker}: unsupported or damaged format; point SELKA_VERIFICATION_SHARED_CACHE at a new empty root")
        else:
            self._write_atomic(marker, json.dumps(FORMAT).encode())
        self._depth = 0
        self._descriptor = None
        self.collect_if_due()

    # -- leases ------------------------------------------------------------------------------------------------------

    @contextmanager
    def lease(self):
        """A shared process lease: a collection waits for no one and skips a store someone holds. Nests."""
        if self._depth:
            self._depth += 1
            try:
                yield self
            finally:
                self._depth -= 1
            return
        descriptor = os.open(self.directory / ".retention.lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_SH)
            self._depth = 1
            yield self
        finally:
            self._depth = 0
            os.close(descriptor)

    # -- records -----------------------------------------------------------------------------------------------------

    def _path(self, kind: str, checker: str, digest: str) -> Path:
        return self.directory / kind / checker[:24] / digest[:2] / digest

    @staticmethod
    def _write_atomic(path: Path, data: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".tmp-", dir=path.parent)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(data)
            os.replace(temporary, path)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass

    def get(self, kind: str, checker: str, digest: str) -> str | None:
        """The stored verdict, or None (missing, damaged, or evicted). A hit refreshes the record's use time."""
        path = self._path(kind, checker, digest)
        try:
            data = path.read_bytes()
            verdict = _decode(kind, checker, digest, data)
            if verdict is not None and time.time() - path.stat().st_mtime > TOUCH_AFTER_SECONDS:
                os.utime(path)
            return verdict
        except OSError:
            return None

    def get_many(self, kind: str, checker: str, digests) -> dict[str, str]:
        with self.lease():
            found = {}
            for digest in digests:
                verdict = self.get(kind, checker, digest)
                if verdict is not None:
                    found[digest] = verdict
            return found

    def put_many(self, kind: str, checker: str, verdicts: dict[str, str]) -> int:
        """Publish verdicts that are not stored yet. One that differs from a stored verdict is not published: the stored one is
        kept and the difference is logged. Returns how many were published."""
        published = 0
        with self.lease():
            for digest, verdict in verdicts.items():
                path = self._path(kind, checker, digest)
                existing = self.get(kind, checker, digest)
                if existing == verdict:
                    continue
                if existing is not None:
                    with open(self.directory / "mismatches.log", "a") as log:
                        log.write(f"mismatch {kind} {checker[:24]} {digest} existing={existing!r} attempted={verdict!r}\n")
                    continue
                self._write_atomic(path, _record(kind, checker, digest, verdict))
                published += 1
        return published

    # -- a checker's first complete run ------------------------------------------------------------------------------

    def established(self, kind: str, checker: str) -> bool:
        """Whether a run has completed with this checker, so that the verdicts of the functions it was asked about are here."""
        return (self.directory / kind / checker[:24] / MARKER).exists()

    def establish(self, kind: str, checker: str) -> None:
        with self.lease():
            self._write_atomic(self.directory / kind / checker[:24] / MARKER, b"complete\n")

    # -- retention ---------------------------------------------------------------------------------------------------

    def collect_if_due(self) -> dict | None:
        """Collect when an hour has passed since the last collection of this store (any process)."""
        stamp = self.directory / "last-collection"
        try:
            if time.time() - stamp.stat().st_mtime < self.interval:
                return None
        except OSError:
            pass
        return self.collect()

    def collect(self, max_entries: int | None = None) -> dict:
        """Evict the least recently used verdicts beyond `max_entries`. Takes the exclusive lease without waiting: a store that
        a process is reading or writing is skipped and reported. Markers, logs and locks are never removed."""
        limit = self.max_entries if max_entries is None else max_entries
        descriptor = os.open(self.directory / ".retention.lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                return {"skipped": "in use"}
            records = []
            for kind in ("zig", "lean", "mutants"):
                base = self.directory / kind
                if not base.is_dir():
                    continue
                for path in base.glob("*/??/*"):
                    if path.is_file() and not path.name.startswith(".tmp-"):
                        try:
                            records.append((path.stat().st_mtime, str(path)))
                        except OSError:
                            pass
            removed = 0
            if len(records) > limit:
                records.sort()
                for _, path in records[: len(records) - limit]:
                    try:
                        os.unlink(path)
                        removed += 1
                    except OSError:
                        pass
            (self.directory / "last-collection").write_text(str(int(time.time())))
            return {"scanned": len(records), "removed": removed, "retained": len(records) - removed}
        finally:
            os.close(descriptor)
