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
LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()


class SnapshotError(RuntimeError):
    """An input or watcher failure prevents a reusable verification result."""


_CHUNK_SIZE = 1 << 20
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

    def relevant(self, name: bytes, mask: int) -> bool:
        if not name:
            return True
        if name in self.names:
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
    def __init__(self) -> None:
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

    def add(self, path: Path, *, directory: bool) -> _Watch:
        if path in self.paths:
            return self.watches[self.paths[path]]
        mask = _MASK | _DONT_FOLLOW | (_ONLYDIR if directory else 0)
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), mask)
        if wd < 0:
            raise SnapshotError(f"cannot watch {path}: {os.strerror(ctypes.get_errno())}")
        watch = self.watches.setdefault(wd, _Watch())
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


class Snapshot:
    """Watch and stream-hash declared inputs until the context is released.

    identity is a JSON-serializable content identity, independent of timestamps.
    unchanged() permanently rejects observed mutations, including restored bytes
    and mtimes (ABA). Missing required inputs and watcher errors raise SnapshotError.
    Directory symlinks within a recursive recipe are not traversed, matching
    input_manifest's os.walk(followlinks=False); a declared base symlink is followed.
    """

    def __init__(self, root: Path, recipes: list[str], extra_files: list[Path] | None = None) -> None:
        self._requested_root = Path(root).absolute()
        self.recipes = list(recipes)
        self.extra_files = list(extra_files or ())
        self._watcher: _Inotify | None = None
        self._paths: dict[Path, tuple[bool, tuple[int, ...]]] = {}
        self._links: dict[str, str] = {}
        self._identity: dict | None = None
        self._entered = False

    @property
    def identity(self) -> dict:
        if self._identity is None or self._watcher is None:
            raise SnapshotError("snapshot identity is only available in an active context")
        return copy.deepcopy(self._identity)

    def __enter__(self) -> Snapshot:
        if self._entered:
            raise SnapshotError("a snapshot cannot be entered more than once")
        self._entered = True
        self._watcher = _Inotify()
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
            self._identity = {"format": 1, "recipes": self.recipes, "files": files,
                              "symlinks": dict(sorted(self._links.items()))}
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
        directory = stat.S_ISDIR(value.st_mode)
        identity = _directory_identity(value) if directory else _file_identity(value)
        previous = self._paths.setdefault(path, (directory, identity))
        if previous != (directory, identity):
            self._watcher.dirty = True
            raise SnapshotError(f"input changed while watches were installed: {path}")

    def _resolve(self, path: Path, links: int = 0) -> Path:
        if links > 40:
            raise SnapshotError(f"too many symlinks in declared input: {path}")
        current = Path(path.anchor)
        self._observe(current, current.lstat())
        parts = path.parts[1:]
        for index, name in enumerate(parts):
            if name == "..":
                current = current.parent
                continue
            watch = self._watcher.add(current, directory=True)
            watch.names.add(os.fsencode(name))
            candidate = current / name
            before = candidate.lstat()
            self._observe(candidate, before)
            if stat.S_ISLNK(before.st_mode):
                target = os.readlink(candidate)
                self._links[self._label(candidate)] = target
                if _file_identity(candidate.lstat()) != _file_identity(before):
                    raise SnapshotError(f"symlink changed while resolving input: {candidate}")
                destination = Path(target)
                if not destination.is_absolute():
                    destination = current / destination
                return self._resolve(destination.joinpath(*parts[index + 1:]), links + 1)
            current = candidate
        return current

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
        with os.scandir(actual) as entries:
            ordered = sorted(entries, key=lambda entry: entry.name)
        for entry in ordered:
            name = entry.name
            if name.startswith("."):
                continue
            logical = base / name
            if entry.is_symlink():
                if name.endswith(".pyc") or not name.endswith(suffix):
                    continue
                # Classify under watched target parents, including a target that
                # is a directory today but could be replaced with a matching file.
                target = self._resolve(logical)
                is_directory = stat.S_ISDIR(target.lstat().st_mode)
            else:
                is_directory = entry.is_dir(follow_symlinks=False)
            if is_directory:
                if recursive and name != "__pycache__" and not entry.is_symlink():
                    found.extend(self._expand(logical, suffix, True))
            elif not name.endswith(".pyc") and name.endswith(suffix):
                self._required_file(logical)
                found.append(logical)
        return found

    def _hash_file(self, path: Path) -> tuple[str, int]:
        before = path.lstat()
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
        fd = os.open(path, flags)
        with os.fdopen(fd, "rb") as handle:
            opened = os.fstat(handle.fileno())
            if not stat.S_ISREG(opened.st_mode) or _file_identity(opened) != _file_identity(before):
                raise SnapshotError(f"input changed before hashing: {path}")
            digest = hashlib.sha256()
            size = 0
            while chunk := handle.read(_CHUNK_SIZE):
                digest.update(chunk)
                size += len(chunk)
            after = os.fstat(handle.fileno())
        if (_file_identity(before) != _file_identity(after) or
                _file_identity(path.lstat()) != _file_identity(before) or size != before.st_size):
            raise SnapshotError(f"input changed while hashing: {path}")
        self._observe(path, after)
        return digest.hexdigest(), size

    def unchanged(self) -> bool:
        """Reject relevant events or changed path identities without rehashing files."""
        if self._watcher is None or self._identity is None:
            raise SnapshotError("snapshot is not active")
        clean = self._watcher.drain()
        for path, (directory, identity) in self._paths.items():
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
