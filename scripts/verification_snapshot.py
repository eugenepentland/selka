"""Content snapshots with scoped Linux mutation detection for verification receipts.

Recipes have the same expansion rules as tests/input_manifest.py: a required
literal file, a required recursive directory ending in '/', a direct 'dir/*'
suffix glob, or a recursive 'dir/**/*' suffix glob. Expanded directories exclude
hidden entries, __pycache__ directories and .pyc files. Literal inputs are required
even when their names would be excluded from a directory recipe.

Keep the context open through publication and check unchanged() after publishing
as well as before. External writers cannot be locked atomically by this helper;
the coordinator must discard a publication if the final check fails.
"""
from __future__ import annotations

import copy
from contextlib import contextmanager
from contextvars import ContextVar
from collections import OrderedDict
from collections.abc import Iterable
import ctypes
from dataclasses import dataclass, field
import hashlib
import marshal
import os
from pathlib import Path
import stat
import struct
import sys


# Bind the code Python actually compiled, including its function bodies and
# constants, rather than later source bytes read after module initialization.
_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()


class SnapshotError(RuntimeError):
    """An input or watcher failure prevents a reusable verification result."""


_CHUNK_SIZE = 1 << 20
_MAX_MEMBERSHIP_ROOTS = 1024
_MAX_MEMBERSHIP_ENTRIES = 65536
_MODIFY = 0x00000002
_ATTRIB = 0x00000004
_CLOSE_WRITE = 0x00000008
_MOVED_FROM = 0x00000040
_MOVED_TO = 0x00000080
_CREATE = 0x00000100
_DELETE = 0x00000200
_DELETE_SELF = 0x00000400
_MOVE_SELF = 0x00000800
_UNMOUNT = 0x00002000
_Q_OVERFLOW = 0x00004000
_IGNORED = 0x00008000
_ONLYDIR = 0x01000000
_DONT_FOLLOW = 0x02000000
_ISDIR = 0x40000000
_MASK = (_MODIFY | _ATTRIB | _CLOSE_WRITE | _MOVED_FROM | _MOVED_TO |
         _CREATE | _DELETE | _DELETE_SELF | _MOVE_SELF | _UNMOUNT)
_EVENT = struct.Struct("iIII")


@dataclass
class _Watch:
    names: set[bytes] = field(default_factory=set)
    scopes: set[tuple[str, bool]] = field(default_factory=set)
    file: bool = False
    include_hidden: bool = False
    membership: bool = False

    def relevant(self, name: bytes, mask: int) -> bool:
        if not name:
            return True
        if name in self.names:
            return True
        if self.membership:
            return True
        if self.include_hidden and self.scopes:
            return True
        text = os.fsdecode(name)
        if text.startswith("."):
            return False
        # A declared directory certifies its visible entry set, even when its
        # suffix glob selected no files. This also detects a newly shadowing PATH
        # executable for the coordinator's deliberately unmatched scope glob.
        if mask & _ISDIR:
            return bool(self.scopes) and text != "__pycache__"
        return bool(self.scopes) and not text.endswith(".pyc")


class _Inotify:
    def __init__(self, include_hidden: bool = False) -> None:
        if sys.platform != "linux":
            raise SnapshotError("verification snapshots require Linux inotify")
        try:
            self.libc = ctypes.CDLL(None, use_errno=True)
            self.libc.inotify_init1.argtypes = [ctypes.c_int]
            self.libc.inotify_init1.restype = ctypes.c_int
            self.libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
            self.libc.inotify_add_watch.restype = ctypes.c_int
            self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        except (AttributeError, OSError) as error:
            raise SnapshotError(f"cannot initialize inotify: {error}") from error
        if self.fd < 0:
            raise SnapshotError(f"inotify_init1 failed: {os.strerror(ctypes.get_errno())}")
        self.watches: dict[int, _Watch] = {}
        self.paths: dict[Path, int] = {}
        self.dirty = False
        self.failure: str | None = None
        self.include_hidden = include_hidden

    def add(self, path: Path, *, directory: bool) -> _Watch:
        if path in self.paths:
            return self.watches[self.paths[path]]
        mask = _MASK | _DONT_FOLLOW | (_ONLYDIR if directory else 0)
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), mask)
        if wd < 0:
            raise SnapshotError(f"cannot watch {path}: {os.strerror(ctypes.get_errno())}")
        watch = self.watches.setdefault(wd, _Watch(include_hidden=self.include_hidden))
        self.paths[path] = wd
        watch.file = watch.file or not directory
        return watch

    def drain(self) -> bool:
        if self.failure is not None:
            raise SnapshotError(self.failure)
        try:
            return self._drain()
        except SnapshotError as error:
            self.failure = str(error)
            raise

    def _drain(self) -> bool:
        while True:
            try:
                data = os.read(self.fd, 1 << 16)
            except BlockingIOError:
                return not self.dirty
            except InterruptedError:
                continue
            except OSError as error:
                raise SnapshotError(f"cannot read inotify: {error}") from error
            if not data:
                raise SnapshotError("inotify unexpectedly closed")
            at = 0
            while at < len(data):
                if len(data) - at < _EVENT.size:
                    raise SnapshotError("truncated inotify event")
                wd, mask, _cookie, length = _EVENT.unpack_from(data, at)
                at += _EVENT.size
                if length > len(data) - at:
                    raise SnapshotError("truncated inotify event name")
                name = data[at:at + length].split(b"\0", 1)[0]
                at += length
                if mask & _Q_OVERFLOW:
                    raise SnapshotError("inotify queue overflow; input history is incomplete")
                watch = self.watches.get(wd)
                if watch is None:
                    raise SnapshotError("unknown inotify watch; input history is incomplete")
                if mask & _IGNORED:
                    if not self.dirty:
                        raise SnapshotError("inotify watch was unexpectedly removed")
                    continue
                if mask & (_DELETE_SELF | _MOVE_SELF | _UNMOUNT):
                    self.dirty = True
                elif mask & _MASK and watch.relevant(name, mask):
                    self.dirty = True

    def close(self) -> None:
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1


def _file_identity(value: os.stat_result) -> tuple[int, ...]:
    return (value.st_dev, value.st_ino, value.st_mode, value.st_uid, value.st_gid,
            value.st_ctime_ns, value.st_mtime_ns, value.st_size)


def _directory_identity(value: os.stat_result) -> tuple[int, ...]:
    # Parent entry-set times also change for unrelated generated outputs. The
    # named-child watches, not those times, certify the relevant path components.
    return value.st_dev, value.st_ino, stat.S_IFMT(value.st_mode)


class DigestSession:
    """Reuse hashes only across overlapping, still-watched snapshots in one process.

    This is bounded scratch, never a persisted metadata-to-digest index. Closing
    the source snapshot, a relevant event or watcher failure removes its authority.
    The receiving snapshot installs its own watch before consulting this session.
    """

    def __init__(self, max_entries: int = 16384) -> None:
        if type(max_entries) is not int or not 0 <= max_entries <= 65536:
            raise ValueError("digest session bound must be between 0 and 65536")
        self.max_entries = max_entries
        self._entries: dict[Path, tuple] = {}
        self._pid = os.getpid()

    def _current_process(self) -> None:
        if self._pid != os.getpid():
            # Forked readers must not consume the parent's watch queue as proof.
            self._entries.clear()
            self._pid = os.getpid()

    def lookup(self, path: Path, metadata: os.stat_result) -> tuple[str, int] | None:
        self._current_process()
        entry = self._entries.get(path)
        if entry is None:
            return None
        identity, result, owner = entry
        if (owner._pid != os.getpid() or owner._watcher is None or identity != _file_identity(metadata)
                or not owner._watcher.drain()):
            self._entries.pop(path, None)
            return None
        return result

    def remember(self, path: Path, metadata: os.stat_result,
                 result: tuple[str, int], owner: Snapshot) -> None:
        self._current_process()
        if path in self._entries or len(self._entries) < self.max_entries:
            self._entries[path] = (_file_identity(metadata), result, owner)


_ACTIVE_RETAINED = ContextVar("verification_retained_session", default=None)


class RetainedSession:
    """Bounded process-local ownership of live validated snapshots.

    activate() admits leases from ordinary Snapshot contexts. Bounds account for
    inventories, metadata paths, watches and watch selectors; oversized or busy
    requests remain transient. No authority survives close, reset or fork.
    """

    def __init__(self, max_snapshots: int = 16, max_entries: int = 262144) -> None:
        for value in (max_snapshots, max_entries):
            if type(value) is not int or not 0 <= value <= 1048576:
                raise ValueError("retained bounds must be integers between 0 and 1048576")
        self.max_snapshots = max_snapshots
        self.max_entries = max_entries
        self._owners = OrderedDict()
        self._retired = {}
        self._transient = set()
        self._pid = os.getpid()
        self._closed = False
        self._statistics = dict(files_hashed=0, bytes_hashed=0, digest_reuses=0,
                                directories_enumerated=0, metadata_observations=0,
                                validation_calls=0, snapshot_reuses=0)

    @property
    def statistics(self):
        """Detached cumulative work counters; request boundaries use deltas."""
        return dict(self._statistics)

    def _record(self, work):
        for key, value in work.items():
            self._statistics[key] += value

    def __enter__(self):
        if self._closed:
            raise SnapshotError("retained session is closed")
        return self

    def __exit__(self, *_args):
        self.close()

    @contextmanager
    def activate(self):
        if self._closed:
            raise SnapshotError("retained session is closed")
        token = _ACTIVE_RETAINED.set(self)
        try:
            yield self
        finally:
            _ACTIVE_RETAINED.reset(token)

    def reset(self):
        """Drop retained authority without rebasing any outstanding borrower."""
        for owner, _borrowers, _cost in self._owners.values():
            owner._close()
        self._owners.clear()
        for owner in self._retired:
            owner._close()
        self._retired.clear()
        for owner in self._transient:
            owner._close()
        self._transient.clear()
        self._pid = os.getpid()

    def close(self):
        self.reset()
        self._closed = True

    @staticmethod
    def _cost(owner):
        watcher = owner._watcher
        identity = owner._identity
        membership = identity.get("directory_membership", ())
        # Declaration lists and key tuples also retain metadata, including
        # duplicate declarations. One entry covers ordinary short text; long
        # path/name payloads consume additional 256-byte units.
        declarations = [owner._requested_root, *owner.recipes,
                        *owner.extra_files, *owner.directory_membership]
        texts = [*declarations, *owner._paths, *owner._missing,
                 *owner._links, *owner._links.values(), *watcher.paths]
        texts.extend(row["path"] for row in identity["files"])
        texts.extend(entry["name"] for row in membership for entry in row.get("entries", ()))
        texts.extend(name for watch in watcher.watches.values() for name in watch.names)
        payload = sum(max(0, (len(value if isinstance(value, bytes)
                                 else os.fsencode(str(value))) - 1) // 256) for value in texts)
        return (2 * len(declarations) + payload
                + len(owner._paths) + len(owner._missing) + len(owner._links)
                + len(identity["files"]) + sum(len(row.get("entries", ())) for row in membership)
                + len(watcher.paths) + len(watcher.watches)
                + sum(len(w.names) + len(w.scopes) for w in watcher.watches.values()))

    def _acquire(self, borrower):
        if self._closed:
            raise SnapshotError("retained session is closed")
        if self._pid != os.getpid():
            self.reset()
        key = (str(borrower._requested_root), tuple(borrower.recipes),
               tuple(str(borrower._input_path(p)) for p in borrower.extra_files),
               borrower.include_hidden, tuple(map(str, borrower.directory_membership)))
        entry = self._owners.get(key)
        rejected_work = {}
        if entry is not None:
            owner, count, cost = entry
            before = owner.statistics
            try:
                clean = owner.unchanged()
            except SnapshotError:
                clean = False
            if clean:
                self._owners.move_to_end(key)
                self._owners[key] = (owner, count + 1, cost)
                borrower._statistics = {k: owner._statistics[k] - before[k] for k in before}
                borrower._statistics["snapshot_reuses"] = 1
                self._record(borrower._statistics)
                return owner, key
            rejected_work = {k: owner._statistics[k] - before[k] for k in before}
            # Existing borrowers stay attached to the dirty original revision.
            self._owners.pop(key)
            if count:
                self._retired[owner] = (count, cost)
            else:
                owner._close()
        owner = Snapshot(borrower._requested_root, borrower.recipes, borrower.extra_files,
                         include_hidden=borrower.include_hidden,
                         directory_membership=borrower.directory_membership,
                         digest_session=borrower._digest_session)
        owner._entered = True
        owner._enter_fresh()
        # Hash sharing is request scratch, not a retained owner dependency.
        owner._digest_session = None
        borrower._statistics = owner.statistics
        for statistic, value in rejected_work.items():
            borrower._statistics[statistic] += value
        self._record(borrower._statistics)
        cost = self._cost(owner)
        while (len(self._owners) + len(self._retired) >= self.max_snapshots or
               sum(item[2] for item in self._owners.values())
               + sum(item[1] for item in self._retired.values()) + cost > self.max_entries):
            idle = next((k for k, item in self._owners.items() if not item[1]), None)
            if idle is None:
                self._transient.add(owner)
                return owner, None
            self._owners.pop(idle)[0]._close()
        self._owners[key] = (owner, 1, cost)
        return owner, key

    def _release(self, owner, key):
        entry = self._owners.get(key)
        if owner in self._transient:
            self._transient.remove(owner)
            owner._close()
        elif owner in self._retired:
            count, cost = self._retired[owner]
            if count == 1:
                self._retired.pop(owner)
                owner._close()
            else:
                self._retired[owner] = (count - 1, cost)
        elif entry is None or entry[0] is not owner:
            owner._close()
        else:
            self._owners[key] = (owner, entry[1] - 1, entry[2])


class Snapshot:
    """Watch and stream-hash declared inputs until the context is released.

    identity is a JSON-serializable content identity. File recipes do not bind
    timestamps; optional membership scopes bind direct file metadata too, so
    changed search candidates invalidate reuse without hashing unrelated files.
    unchanged() permanently rejects observed mutations, including restored bytes
    and mtimes (ABA). Missing required inputs and watcher errors raise SnapshotError.
    Directory symlinks within a recursive recipe are not traversed, matching
    input_manifest's os.walk(followlinks=False); a declared base symlink is followed.
    include_hidden also inventories dot files and Python cache files, for native
    experiment contracts. That mode rejects directory symlinks inside recursive
    scopes: their external contents need an explicit, independently watched scope.
    directory_membership inventories only immediate entries, including hidden
    names, resolving child aliases without traversing directory targets or hashing
    contents. File alias targets are watched even if the loader currently rejects
    them: their later compatibility may change provider selection. Missing roots
    are allowed and watched through their nearest existing ancestor. Membership
    identities include file metadata; actual provider bytes need explicit inputs.
    """

    def __init__(self, root: Path, recipes: list[str], extra_files: list[Path] | None = None,
                 *, include_hidden: bool = False,
                 directory_membership: Iterable[Path] = (),
                 digest_session: DigestSession | None = None) -> None:
        self._requested_root = Path(root).absolute()
        self.recipes = list(recipes)
        self.extra_files = list(extra_files or ())
        self._watcher: _Inotify | None = None
        self._paths: dict[Path, tuple[bool, tuple[int, ...]]] = {}
        self._links: dict[str, str] = {}
        self._identity: dict | None = None
        self._entered = False
        self._pid = os.getpid()
        self._lease = None
        self.include_hidden = include_hidden
        self.directory_membership = []
        for path in directory_membership:
            if len(self.directory_membership) >= _MAX_MEMBERSHIP_ROOTS:
                raise SnapshotError("too many directory membership roots")
            self.directory_membership.append(self._input_path(path))
        self._missing: set[Path] = set()
        self._digest_session = digest_session
        self._statistics = dict(files_hashed=0, bytes_hashed=0, digest_reuses=0,
                                directories_enumerated=0, metadata_observations=0,
                                validation_calls=0, snapshot_reuses=0)

    @property
    def statistics(self) -> dict[str, int]:
        """Actual snapshot work, separate from content identities and cache keys."""
        return dict(self._statistics)

    @property
    def identity(self) -> dict:
        if self._lease is not None:
            return self._lease[1].identity
        if self._identity is None or self._watcher is None:
            raise SnapshotError("snapshot identity is only available in an active context")
        return copy.deepcopy(self._identity)

    def __enter__(self) -> Snapshot:
        if self._entered:
            raise SnapshotError("a snapshot cannot be entered more than once")
        self._entered = True
        session = _ACTIVE_RETAINED.get()
        if session is not None:
            owner, key = session._acquire(self)
            self._lease = (session, owner, key)
            self.root = owner.root
            return self
        return self._enter_fresh()

    def _enter_fresh(self):
        self._watcher = _Inotify(self.include_hidden)
        try:
            self.root = self._resolve(self._requested_root)
            if not self.root.is_dir():
                raise SnapshotError(f"snapshot root is not a directory: {self.root}")
            paths: set[Path] = set()
            # Resolve and watch each declared scope before its first enumeration.
            for recipe in self.recipes:
                base, suffix, recursive = self._recipe(recipe)
                if suffix is None:
                    self._required_file(base)
                    paths.add(base)
                else:
                    paths.update(self._expand(base, suffix, recursive))
            for extra in self.extra_files:
                path = self._input_path(extra)
                self._required_file(path)
                paths.add(path)
            files = []
            for path in sorted(paths, key=lambda item: self._label(item)):
                actual = self._required_file(path)
                digest, size = self._hash_file(actual)
                metadata = actual.lstat()
                self._observe(actual, metadata)
                item = {"path": self._label(path), "sha256": digest, "size": size,
                        "mode": stat.S_IMODE(metadata.st_mode),
                        "uid": metadata.st_uid, "gid": metadata.st_gid}
                if path != actual:
                    item["resolved"] = self._label(actual)
                files.append(item)
            membership = [self._membership(path) for path in
                          sorted(set(self.directory_membership), key=str)]
            self._identity = {"format": 1, "recipes": self.recipes, "files": files,
                              "symlinks": dict(sorted(self._links.items()))}
            if self.directory_membership:
                self._identity["directory_membership"] = membership
            if self.include_hidden:
                self._identity["include_hidden"] = True
            if not self.unchanged():
                raise SnapshotError("declared inputs changed while constructing the snapshot")
            return self
        except SnapshotError:
            self._close()
            raise
        except (OSError, ValueError, RuntimeError) as error:
            self._close()
            raise SnapshotError(f"cannot snapshot declared inputs: {error}") from error

    def __exit__(self, _kind, _value, _traceback) -> None:
        self.close()

    def close(self) -> None:
        """Release watches; subsequent identity or unchanged() access is an error."""
        if self._lease is not None:
            session, owner, key = self._lease
            self._lease = None
            session._release(owner, key)
        else:
            self._close()

    def _close(self) -> None:
        if self._watcher is not None:
            self._watcher.close()
            self._watcher = None

    def _input_path(self, path: str | Path) -> Path:
        value = Path(path)
        return value if value.is_absolute() else self._requested_root / value

    def _label(self, path: Path) -> str:
        try:
            return path.relative_to(self._requested_root).as_posix()
        except ValueError:
            return str(path)

    def _observe(self, path: Path, value: os.stat_result) -> None:
        self._statistics["metadata_observations"] += 1
        directory = stat.S_ISDIR(value.st_mode)
        identity = _directory_identity(value) if directory else _file_identity(value)
        previous = self._paths.setdefault(path, (directory, identity))
        if previous != (directory, identity):
            self._watcher.dirty = True
            raise SnapshotError(f"input changed while watches were installed: {path}")

    def _resolve(self, path: Path, links: int = 0, *, allow_missing: bool = False) -> Path | None:
        if links > 40:
            raise SnapshotError(f"too many symlinks in declared input: {path}")
        current = Path(path.anchor)
        self._observe(current, current.lstat())
        parts = path.parts[1:]
        for index, name in enumerate(parts):
            if name == "..":
                current = current.parent
                continue
            if allow_missing and not stat.S_ISDIR(current.lstat().st_mode):
                self._watcher.add(current, directory=False)
                self._missing.add(current.joinpath(*parts[index:]))
                return None
            watch = self._watcher.add(current, directory=True)
            watch.names.add(os.fsencode(name))
            candidate = current / name
            try:
                before = candidate.lstat()
            except FileNotFoundError:
                if not allow_missing:
                    raise
                self._missing.add(candidate)
                return None
            self._observe(candidate, before)
            if stat.S_ISLNK(before.st_mode):
                target = os.readlink(candidate)
                self._links[self._label(candidate)] = target
                if _file_identity(candidate.lstat()) != _file_identity(before):
                    raise SnapshotError(f"symlink changed while resolving input: {candidate}")
                destination = Path(target)
                if not destination.is_absolute():
                    destination = current / destination
                return self._resolve(destination.joinpath(*parts[index + 1:]), links + 1,
                                     allow_missing=allow_missing)
            current = candidate
        return current

    def _membership(self, path: Path) -> dict:
        item = {"path": self._label(path)}
        actual = self._resolve(path, allow_missing=True)
        if actual is None:
            return {**item, "status": "missing"}
        if path != actual:
            item["resolved"] = self._label(actual)
        metadata = actual.lstat()
        self._observe(actual, metadata)
        if not stat.S_ISDIR(metadata.st_mode):
            self._watcher.add(actual, directory=False)
            return {**item, "status": "not-directory", "metadata": list(_file_identity(metadata))}
        # Install the direct watch before even the first enumeration. Every name
        # is relevant, but no child directory or directory alias target is traversed.
        self._watcher.add(actual, directory=True).membership = True
        entries = []
        self._statistics["directories_enumerated"] += 1
        with os.scandir(actual) as directory:
            for entry in directory:
                if len(entries) >= _MAX_MEMBERSHIP_ENTRIES:
                    raise SnapshotError(f"too many directory membership entries: {path}")
                value = entry.stat(follow_symlinks=False)
                row = {"name": entry.name, "kind": stat.S_IFMT(value.st_mode)}
                if stat.S_ISDIR(value.st_mode):
                    # Nested writes change directory times and do not alter a
                    # direct loader search. Bind permissions, not those times.
                    row["metadata"] = [stat.S_IMODE(value.st_mode), value.st_uid, value.st_gid]
                else:
                    row["metadata"] = list(_file_identity(value))
                if stat.S_ISLNK(value.st_mode):
                    row["target"] = os.readlink(actual / entry.name)
                    if _file_identity((actual / entry.name).lstat()) != _file_identity(value):
                        raise SnapshotError(f"membership alias changed during listing: {entry.name}")
                    row["resolved_target"] = self._membership_alias(actual / entry.name)
                entries.append(row)
        item.update(status="directory", entries=sorted(entries, key=lambda entry: entry["name"]),
                    metadata=[stat.S_IMODE(metadata.st_mode), metadata.st_uid, metadata.st_gid])
        return item

    def _membership_alias(self, path: Path) -> dict:
        # Watching only link text misses writes to an external candidate target:
        # an incompatible ELF may become loadable during work, then be restored.
        actual = self._resolve(path, allow_missing=True)
        if actual is None:
            return {"status": "missing"}
        value = actual.lstat()
        self._observe(actual, value)
        if stat.S_ISDIR(value.st_mode):
            metadata = [stat.S_IMODE(value.st_mode), value.st_uid, value.st_gid]
        else:
            self._watcher.add(actual, directory=False)
            metadata = list(_file_identity(value))
        return {"status": "present", "path": self._label(actual),
                "kind": stat.S_IFMT(value.st_mode), "metadata": metadata}

    def _required_file(self, path: Path) -> Path:
        actual = self._resolve(path)
        before = actual.lstat()
        if not stat.S_ISREG(before.st_mode):
            raise SnapshotError(f"declared input is not a regular file: {path}")
        self._watcher.add(actual, directory=False)
        self._observe(actual, actual.lstat())
        return actual

    def _recipe(self, recipe: str) -> tuple[Path, str | None, bool]:
        if not recipe:
            raise SnapshotError("empty declared input recipe")
        if recipe.endswith("/"):
            return self._input_path(recipe[:-1] or "/"), "", True
        if "/**/*" in recipe:
            base, suffix = recipe.split("/**/*", 1)
            recursive = True
        elif "/*" in recipe:
            base, suffix = recipe.split("/*", 1)
            recursive = False
        else:
            return self._input_path(recipe), None, False
        if not base or any(char in suffix for char in "/*?["):
            raise SnapshotError(f"unsupported declared input glob: {recipe}")
        return self._input_path(base), suffix, recursive

    def _expand(self, base: Path, suffix: str, recursive: bool) -> list[Path]:
        actual = self._resolve(base)
        if not stat.S_ISDIR(actual.lstat().st_mode):
            raise SnapshotError(f"declared recipe names no directory: {base}")
        self._watcher.add(actual, directory=True).scopes.add((suffix, recursive))
        found = []
        self._statistics["directories_enumerated"] += 1
        with os.scandir(actual) as entries:
            ordered = sorted(entries, key=lambda entry: entry.name)
        for entry in ordered:
            name = entry.name
            if not self.include_hidden and name.startswith("."):
                continue
            logical = base / name
            if entry.is_symlink():
                if (not self.include_hidden and name.endswith(".pyc")) or not name.endswith(suffix):
                    continue
                # Classify under watched target parents, including a target that
                # is a directory today but could be replaced with a matching file.
                target = self._resolve(logical)
                is_directory = stat.S_ISDIR(target.lstat().st_mode)
            else:
                is_directory = entry.is_dir(follow_symlinks=False)
            if is_directory:
                if recursive and self.include_hidden and entry.is_symlink():
                    raise SnapshotError(f"inclusive recursive scope contains a directory symlink: {logical}")
                if recursive and (self.include_hidden or name != "__pycache__") and not entry.is_symlink():
                    found.extend(self._expand(logical, suffix, True))
            elif (self.include_hidden or not name.endswith(".pyc")) and name.endswith(suffix):
                self._required_file(logical)
                found.append(logical)
        return found

    def _hash_file(self, path: Path) -> tuple[str, int]:
        before = path.lstat()
        if self._digest_session is not None:
            reused = self._digest_session.lookup(path, before)
            if reused is not None:
                self._observe(path, before)
                self._statistics["digest_reuses"] += 1
                return reused
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
        fd = os.open(path, flags)
        with os.fdopen(fd, "rb") as handle:
            opened = os.fstat(handle.fileno())
            if not stat.S_ISREG(opened.st_mode) or _file_identity(opened) != _file_identity(before):
                raise SnapshotError(f"input changed before hashing: {path}")
            digest = hashlib.sha256()
            self._statistics["files_hashed"] += 1
            size = 0
            while chunk := handle.read(_CHUNK_SIZE):
                digest.update(chunk)
                size += len(chunk)
                self._statistics["bytes_hashed"] += len(chunk)
            after = os.fstat(handle.fileno())
        if (_file_identity(before) != _file_identity(after) or
                _file_identity(path.lstat()) != _file_identity(before) or size != before.st_size):
            raise SnapshotError(f"input changed while hashing: {path}")
        self._observe(path, after)
        result = digest.hexdigest(), size
        if self._digest_session is not None:
            self._digest_session.remember(path, after, result, self)
        return result

    def unchanged(self) -> bool:
        """Reject relevant events or changed path identities without rehashing files."""
        if self._lease is not None:
            owner = self._lease[1]
            before = owner.statistics
            try:
                return owner.unchanged()
            finally:
                work = {key: value - before[key] for key, value in owner.statistics.items()}
                for key, value in work.items():
                    self._statistics[key] += value
                self._lease[0]._record(work)
        if self._watcher is None or self._identity is None:
            raise SnapshotError("snapshot is not active")
        if self._pid != os.getpid():
            self._close()
            raise SnapshotError("snapshot watcher belongs to another process")
        self._statistics["validation_calls"] += 1
        clean = self._watcher.drain()
        for path in self._missing:
            self._statistics["metadata_observations"] += 1
            try:
                path.lstat()
            except (FileNotFoundError, NotADirectoryError):
                continue
            except OSError as error:
                self._watcher.dirty = True
                raise SnapshotError(f"cannot revalidate absent membership {path}: {error}") from error
            self._watcher.dirty = True
        for path, (directory, identity) in self._paths.items():
            self._statistics["metadata_observations"] += 1
            try:
                current = path.lstat()
            except (FileNotFoundError, NotADirectoryError):
                self._watcher.dirty = True
                continue
            except OSError as error:
                self._watcher.dirty = True
                raise SnapshotError(f"cannot revalidate {path}: {error}") from error
            actual = _directory_identity(current) if directory else _file_identity(current)
            if actual != identity:
                self._watcher.dirty = True
        return self._watcher.drain() and clean
