"""Bounded whole-worktree Git authority, written for the reviewed Guardian provider.

Guardian was turned off on 18 November 2026 (GH-2) and the warm path that used this
module went with it; the gate no longer calls it. It stays, with its tests, until
a later stage of the script removal (GH-6) takes it out.

The identity records Git's observed diff and untracked names, plus actual dirty
file bytes. Directory watches retain mutation history, including clean/dirty ABA
and new paths. Ignore rules only suppress paths Git ignores and never suppress
tracked ancestors. Unsupported providers/configuration fail closed.
"""
from contextlib import ExitStack
from dataclasses import dataclass, field
import hashlib
import os
from pathlib import Path
import subprocess
import selectors
import stat
import time
import sys

import verification_code_identity as code_identity
from verification_snapshot import (Snapshot, SnapshotError, _Inotify, _Watch, _DirtyReasons, _ATTRIB, _MASK,
                                   _directory_identity, _file_identity, _timestamp_granularity_ns)

MAX_OUTPUT = 32 * 1024 * 1024
MAX_PATHS = 150000
MAX_DIRECTORIES = 12000
MAX_DIRTY_BYTES = 64 * 1024 * 1024
MAX_OBJECT_STORE_WATCHES = 8192


class UnsupportedGit(ValueError):
    """A request must execute Guardian because this authority cannot qualify it."""


def command(root, env, *args, input=None, accepted=(0,)):
    """Cap output while reading it, without holding an unbounded communicate buffer."""
    if input is not None and len(input) > MAX_OUTPUT:
        raise UnsupportedGit("Git command input exceeds its bound")
    # Match the reviewed Guardian spawnGit environment, including its read-only
    # optional-lock policy. Never mutate the inherited normalized dictionary.
    child_env = dict(env, LC_ALL="C", GIT_OPTIONAL_LOCKS="0")
    with subprocess.Popen(["git", *args], cwd=root, env=child_env, stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
        output = [bytearray(), bytearray()]
        try:
            with selectors.DefaultSelector() as poller:
                for index, stream in enumerate((child.stdout, child.stderr)):
                    os.set_blocking(stream.fileno(), False)
                    poller.register(stream, selectors.EVENT_READ, index)
                pending = memoryview(input or b"")
                if pending:
                    os.set_blocking(child.stdin.fileno(), False)
                    poller.register(child.stdin, selectors.EVENT_WRITE, 2)
                else:
                    child.stdin.close()
                deadline = time.monotonic() + 30
                while poller.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise UnsupportedGit("Git input command exceeded its deadline")
                    for ready, _ in poller.select(remaining):
                        if ready.data == 2:
                            try:
                                pending = pending[os.write(ready.fd, pending[:65536]):]
                            except BrokenPipeError:
                                pending = memoryview(b"")
                            if not pending:
                                poller.unregister(ready.fileobj)
                                child.stdin.close()
                            continue
                        data = os.read(ready.fd, 65536)
                        if not data:
                            poller.unregister(ready.fileobj)
                            continue
                        output[ready.data].extend(data)
                        if len(output[ready.data]) > MAX_OUTPUT:
                            raise UnsupportedGit("Git input command exceeded its output bound")
                child.wait(timeout=max(0.001, deadline - time.monotonic()))
            if child.returncode not in accepted:
                raise UnsupportedGit("Git input command failed")
            return bytes(output[0])
        except BaseException:
            child.kill()
            child.wait()
            raise


def names(data):
    values = data.rstrip(b"\0").split(b"\0") if data else []
    if len(values) > MAX_PATHS:
        raise UnsupportedGit("Git path inventory exceeds its bound")
    result = [os.fsdecode(value) for value in values]
    if any(not name or "\n" in name or Path(name).is_absolute() or ".." in Path(name).parts for name in result):
        raise UnsupportedGit("Git path inventory has an unsupported name")
    return result


def digest(data):
    return hashlib.sha256(data).hexdigest()


def _object_identity(value):
    """Identity of one object-store file without its times.

    Git freshens an object it would write again (a `utime`, a new hard link from a
    local clone) and never rewrites one: those change a timestamp or a link count and
    no content. A content write is an inotify event, which the authority treats as a
    change, so the times add nothing a tolerated event could have changed.
    """
    return (value.st_dev, value.st_ino, value.st_mode, value.st_uid, value.st_gid, value.st_size)


def _store_identity(value):
    """Directories keep only what names them: their entry-set times move with every added object."""
    return _directory_identity(value) if stat.S_ISDIR(value.st_mode) else _object_identity(value)


@dataclass
class ObjectWatch(_Watch):
    """One object-store directory or object file whose later additions are not inputs.

    Objects are content-addressed and written once, so an entry created after the watch
    was installed (a new loose object, git's `tmp_obj_*` file for it, a new pack and its
    index) cannot change what an installed object or ref resolves to; a different object
    would need a different ref, and the ref guards watch the refs. Every entry present at
    installation stays an input: a delete, move, create over it or content write revokes,
    and an attribute-only event revokes unless the file still has the recorded identity
    without its times. `additive=False` (the `info` directory: alternates, commit-graph
    files) revokes on any event, as before.
    """
    additive: bool = True
    known: dict[bytes, tuple | None] = field(default_factory=dict)
    own: tuple | None = None

    def relevant(self, name, mask):
        if not self.additive:
            return True
        if name and name not in self.known:
            return False
        expected = self.known[name] if name else self.own
        if expected is None or mask & _MASK != _ATTRIB:
            return True
        try:
            return _object_identity(os.lstat(self.path / os.fsdecode(name))) != expected
        except OSError:
            return True


class ObjectStoreAuthority:
    """Bounded object availability history without hashing loose objects or packs.

    Guardian's merge-base and diff readers depend on objects, pack indexes and
    commit graphs, not only refs. Every supported transport inode and directory
    is retained, and any change to what was there revokes this run. Objects added
    later, by this checkout or another worktree sharing the store, do not: see
    `ObjectWatch`. Without that, every commit anywhere in a shared repository
    failed every gate in flight ("inputs changed while awaiting admitted work").
    """

    def __init__(self, path, max_watches=None):
        self.path = Path(path).absolute()
        self.limit = MAX_OBJECT_STORE_WATCHES if max_watches is None else max_watches
        self.watcher = None
        self.paths = {}
        self.failed = False
        self._dirty_reasons = _DirtyReasons()
        self.verification_role = "guardian_git_object_availability"
        self._statistics = dict(files_hashed=0, bytes_hashed=0, directories_enumerated=0,
                                metadata_observations=0, validation_calls=0, object_store_watches=0)

    @property
    def statistics(self):
        return dict(self._statistics)

    def stability_diagnostics(self, role="guardian_git_object_availability"):
        """Report bounded observations only; never poll or revalidate authority."""
        return self._dirty_reasons.report(role, str)

    def _observe(self, path, *, ancestor=False):
        if path in self.paths:
            return self.watcher.watches[self.watcher.paths[path]]
        if len(self.paths) >= self.limit:
            raise UnsupportedGit("Git object-store watch bound exceeded: " + str(self.limit))
        before = path.lstat()
        self._statistics["metadata_observations"] += 1
        directory = stat.S_ISDIR(before.st_mode)
        if not (directory or stat.S_ISREG(before.st_mode)):
            raise UnsupportedGit("aliased or special Git object-store transport")
        if ancestor and not directory:
            raise UnsupportedGit("Git object-store ancestor is not a directory")
        if not ancestor and before.st_dev != self.device:
            raise UnsupportedGit("Git object-store transport crosses filesystems")
        watch = self.watcher.add(path, directory=directory)
        after = path.lstat()
        self._statistics["metadata_observations"] += 1
        if _store_identity(before) != _store_identity(after):
            raise UnsupportedGit("Git object-store transport changed during watch installation")
        if not ancestor and not isinstance(watch, ObjectWatch):
            watch = ObjectWatch(path=watch.path, file=watch.file, include_hidden=watch.include_hidden,
                                own=None if directory else _object_identity(after))
            self.watcher.watches[self.watcher.paths[path]] = watch
        self.paths[path] = (ancestor, _store_identity(after))
        self._statistics["object_store_watches"] = len(self.paths)
        return watch

    def __enter__(self):
        try:
            if _timestamp_granularity_ns(self.path) is None:
                raise UnsupportedGit("Git object-store filesystem has no reviewed local mutation semantics")
            self.watcher = _Inotify(include_hidden=True, reasons=self._dirty_reasons)
            self.device = self.path.lstat().st_dev
            # Retain exact lexical ancestors too: a mount/alias/path replacement
            # must not strand watches on an obsolete object-store directory.
            for parent in reversed(self.path.parents):
                self._observe(parent, ancestor=True).names.add(
                    os.fsencode(self.path.relative_to(parent).parts[0]))
            wave = [self.path]
            info = self.path / "info"
            while wave:
                directory = wave.pop()
                watch = self._observe(directory)
                watch.additive = info not in (directory, *directory.parents)
                if not stat.S_ISDIR(directory.lstat().st_mode):
                    raise UnsupportedGit("Git object-store root is not a directory")
                self._statistics["directories_enumerated"] += 1
                with os.scandir(directory) as entries:
                    for entry in entries:
                        path = directory / entry.name
                        self._observe(path)
                        is_directory = entry.is_dir(follow_symlinks=False)
                        watch.known[os.fsencode(entry.name)] = (
                            None if is_directory else self.paths[path][1])
                        if is_directory:
                            wave.append(path)
            if not self.unchanged():
                raise UnsupportedGit("Git object-store changed during watch installation")
            return self
        except BaseException:
            self.close()
            raise

    def __exit__(self, *_):
        self.close()

    def close(self):
        self.failed = True
        self._dirty_reasons.add("authority", self.path, "Git object-store authority closed", unknown=True)
        if self.watcher is not None:
            self.watcher.close()

    def events_unchanged(self):
        if self.failed or self.watcher is None:
            return False
        # Set the failure before polling so interruption cannot revive authority.
        self.failed = True
        try:
            clean = self.watcher.drain()
        except BaseException:
            self._dirty_reasons.add("authority", self.path, "Git object-store event validation interrupted", unknown=True)
            raise
        self.failed = not clean
        return clean

    def unchanged(self):
        if not self.events_unchanged():
            return False
        self.failed = True
        self._statistics["validation_calls"] += 1
        try:
            for path, (_ancestor, expected) in self.paths.items():
                self._statistics["metadata_observations"] += 1
                if _store_identity(path.lstat()) != expected:
                    self._dirty_reasons.add("path", path, "Git object-store metadata changed")
                    return False
        except OSError as error:
            self._dirty_reasons.add("path", path, "Git object-store metadata unavailable: " + str(error), unknown=True)
            return False
        except BaseException:
            self._dirty_reasons.add("authority", self.path, "Git object-store metadata validation interrupted", unknown=True)
            raise
        try:
            clean = self.watcher.drain()
        except BaseException:
            self._dirty_reasons.add("authority", self.path, "Git object-store final event validation interrupted", unknown=True)
            raise
        self.failed = not clean
        return clean


@dataclass
class TreeWatch(_Watch):
    ignored: set[bytes] = field(default_factory=set)

    def relevant(self, name, mask):
        return not name or name not in self.ignored


class ExactAbsence:
    def __init__(self, paths):
        self.paths = paths
        self.watcher = _Inotify()

    def __enter__(self):
        try:
            for path in self.paths:
                parent = path.parent
                while not parent.exists():
                    parent = parent.parent
                self.watcher.add(parent, directory=True).names.add(os.fsencode(path.relative_to(parent).parts[0]))
            if not self.unchanged():
                raise UnsupportedGit("Git configuration changed during watch installation")
            return self
        except BaseException:
            self.watcher.close()
            raise

    def __exit__(self, *_):
        self.watcher.close()

    def events_unchanged(self):
        return self.watcher.drain()

    def unchanged(self):
        return self.events_unchanged() and all(not path.exists() for path in self.paths)


def configuration_paths(root, env):
    """Refuse extensible/externally executed Git semantics; watch default policy."""
    for name, value in env.items():
        if name.startswith("GIT_") and name not in (
                "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"):
            expected = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
                        "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": ""}
            if name not in expected or value != expected[name]:
                raise UnsupportedGit("Git environment override requires separate review")
    home = Path(env.get("HOME", str(Path.home())))
    xdg = Path(env.get("XDG_CONFIG_HOME", str(home / ".config")))
    if not home.is_absolute() or not xdg.is_absolute():
        raise UnsupportedGit("relative Git home/config provider")
    common = Path(os.fsdecode(command(root, env, "rev-parse", "--git-common-dir")).strip())
    if not common.is_absolute():
        common = root / common
    git_dir = Path(os.fsdecode(command(root, env, "rev-parse", "--absolute-git-dir")).strip())
    paths = {common / "config", git_dir / "config.worktree", git_dir / "HEAD", git_dir / "index", git_dir / "commondir", git_dir / "gitdir", common / "packed-refs", common / "info/exclude", common / "info/attributes",
             git_dir / "info/exclude", git_dir / "info/attributes", Path("/etc/gitattributes"),
             xdg / "git/ignore", xdg / "git/attributes"}
    marker = root / ".git"
    if marker.is_symlink():
        raise UnsupportedGit("aliased Git indirection requires separate review")
    if marker.is_file():
        # The root directory watch detects entry replacement. This inode watch
        # additionally catches retarget/restore through an ignored hardlink.
        paths.add(marker)
    if env.get("GIT_CONFIG_SYSTEM") != "/dev/null":
        paths.add(Path("/etc/gitconfig"))
    if env.get("GIT_CONFIG_GLOBAL") != "/dev/null":
        paths.update((home / ".gitconfig", xdg / "git/config"))
    branch = command(root, env, "symbolic-ref", "-q", "HEAD", accepted=(0, 1)).decode().strip()
    direct = command(root, env, "symbolic-ref", "-q", "--no-recurse", "HEAD", accepted=(0, 1)).decode().strip()
    if direct != branch:
        raise UnsupportedGit("chained symbolic HEAD requires separate review")
    for name in ("refs/heads/main", "refs/heads/master"):
        if command(root, env, "symbolic-ref", "-q", name, accepted=(0, 1)).strip():
            raise UnsupportedGit("symbolic base reference requires separate review")
    if command(root, env, "rev-parse", "--shared-index-path").strip():
        raise UnsupportedGit("split Git index requires separate review")
    for name in ("objects/info/alternates", "objects/info/http-alternates"):
        path = common / name
        if path.exists():
            raise UnsupportedGit("alternate Git object provider requires separate review")
        paths.add(path)
    if branch:
        paths.add(common / branch)
    raw = command(root, env, "config", "--show-origin", "--null", "--list")
    fields = raw.rstrip(b"\0").split(b"\0") if raw else []
    if len(fields) % 2:
        raise UnsupportedGit("malformed Git configuration inventory")
    for origin, entry in zip(fields[::2], fields[1::2]):
        key, _, value = os.fsdecode(entry).partition("\n")
        key = key.lower()
        if (key.startswith(("include.", "includeif.", "filter.", "submodule.", "fsmonitor."))
                or key in ("core.fsmonitor", "core.worktree", "core.ignorestat", "core.sparsecheckout",
                           "core.sparsecheckoutcone", "extensions.partialclone", "diff.orderfile")
                or key == "core.untrackedcache" and value.lower() not in ("false", "no", "off", "0")
                or key.startswith("remote.") and key.endswith(".promisor")
                or key.startswith("diff.") and key.endswith((".command", ".textconv"))
                or key == "diff.external"
                or key == "core.trustctime" and value.lower() not in ("true", "yes", "on", "1")
                or key == "core.checkstat" and value != "default"):
            raise UnsupportedGit("unsupported Git configuration: " + key)
        source = os.fsdecode(origin)
        if not source.startswith("file:"):
            raise UnsupportedGit("non-file Git configuration provider")
        path = Path(source[5:])
        paths.add(path if path.is_absolute() else root / path)
        if key in ("core.attributesfile", "core.excludesfile"):
            resolved = os.fsdecode(command(root, env, "config", "--path", "--get", key)).strip()
            if not Path(resolved).is_absolute():
                raise UnsupportedGit("relative external Git policy path")
            paths.add(Path(resolved))
    return sorted(paths), digest(b"\0".join(fields[1::2]))


class GitTreeAuthority:
    def __init__(self, root, env, session=None):
        self.root, self.env, self.session = Path(root), env, session
        self.stack = ExitStack()
        self.watcher = _Inotify()
        self.guards = []
        self.identity = {}
        self.directories = 0
        self.verification_role = "guardian_worktree_git"

    def __enter__(self):
        try:
            self.stack.callback(self.watcher.close)
            paths, config = configuration_paths(self.root, self.env)
            if any(part.is_symlink() for path in paths for part in (path, *path.parents)):
                raise UnsupportedGit("aliased Git policy path requires separate review")
            existing = [path for path in paths if path.exists()]
            absent = [path for path in paths if not path.exists()]
            self.guards.append(self.stack.enter_context(Snapshot(self.root, [], existing, digest_session=self.session)))
            self.guards.append(self.stack.enter_context(ExactAbsence(absent)))
            tracked_raw = command(self.root, self.env, "ls-files", "-v", "-z")
            records = tracked_raw.rstrip(b"\0").split(b"\0") if tracked_raw else []
            if any(not row.startswith(b"H ") for row in records):
                raise UnsupportedGit("Git index has sparse, unmerged, or assume-unchanged entries")
            tracked = names(b"\0".join(row[2:] for row in records))
            stages = command(self.root, self.env, "ls-files", "--stage", "-z")
            if any(row.startswith(b"160000 ") for row in stages.split(b"\0")):
                raise UnsupportedGit("Git submodules require separate provider authority")
            # Directory events alone miss writes through hardlinks whose names
            # lie in ignored or external directories. Retain inode watches too.
            for name in tracked:
                path = self.root / name
                if path.is_file() or path.is_symlink():
                    self.watcher.add(path, directory=False)
            self._watch_tree(tracked)
            if configuration_paths(self.root, self.env) != (paths, config):
                raise UnsupportedGit("Git configuration changed during watch installation")
            self.identity = dict(self._semantic(), configuration=config,
                                 tracked_index=digest(stages))
            changed = names(command(self.root, self.env, "-c", "diff.autoRefreshIndex=false",
                                    "diff", "--name-only", "--relative", "-z", "HEAD", "--"))
            dirty = []
            for name in changed:
                path = self.root / name
                if path.is_symlink():
                    raise UnsupportedGit("dirty Git symlink requires separate provider authority")
                if path.is_file():
                    dirty.append(path)
            if sum(path.stat().st_size for path in dirty) > MAX_DIRTY_BYTES:
                raise UnsupportedGit("dirty Git input bytes exceed bound")
            snapshot = self.stack.enter_context(Snapshot(self.root, [], dirty, digest_session=self.session))
            self.guards.append(snapshot)
            self.identity["dirty_files"] = snapshot.identity["files"]
            if not self.unchanged():
                raise UnsupportedGit("Git worktree changed during watch installation")
            return self
        except BaseException:
            self.stack.close()
            raise

    def __exit__(self, *_):
        self.stack.close()

    def _watch_tree(self, tracked):
        prefixes = set(tracked)
        for name in tracked:
            prefixes.update(str(parent) for parent in Path(name).parents if str(parent) != ".")
        wave = [self.root]
        while wave:
            entries, views = [], []
            for directory in wave:
                self.directories += 1
                if self.directories > MAX_DIRECTORIES:
                    raise UnsupportedGit("Git worktree directory inventory exceeds bound")
                old = self.watcher.add(directory, directory=True)
                watch = TreeWatch(path=old.path)
                self.watcher.watches[self.watcher.paths[directory]] = watch
                with os.scandir(directory) as scan:
                    children = list(scan)
                for entry in children:
                    path = Path(entry.path)
                    if entry.name in (".gitignore", ".gitattributes"):
                        if entry.is_symlink():
                            raise UnsupportedGit("aliased repository Git policy requires separate review")
                        if entry.is_file(follow_symlinks=False):
                            # Git reads untracked policy too. An ignored or
                            # external hardlink can mutate it without a parent
                            # event, just as with tracked source files.
                            self.watcher.add(path, directory=False)
                    rel = path.relative_to(self.root).as_posix()
                    is_dir = entry.is_dir(follow_symlinks=False)
                    entries.append(rel + ("/" if is_dir else ""))
                    views.append((path, rel, is_dir, watch))
            ignored = set(names(command(self.root, self.env, "check-ignore", "--no-index", "-z", "--stdin",
                                        input=b"\0".join(os.fsencode(name) for name in entries) + b"\0",
                                        accepted=(0, 1)))) if entries else set()
            wave = []
            for path, rel, is_dir, watch in views:
                if (rel + ("/" if is_dir else "")) in ignored and rel not in prefixes and path.name not in (".gitignore", ".gitattributes", ".git"):
                    watch.ignored.add(os.fsencode(path.name))
                    continue
                if is_dir and path.name != ".git":
                    wave.append(path)
            if not self.watcher.drain():
                raise UnsupportedGit("Git worktree changed during recursive watch installation")

    def _semantic(self):
        # Git's porcelain diff can refresh stat-only index entries even with
        # GIT_OPTIONAL_LOCKS=0. Observing inputs must not mutate the watched
        # index. Disabling refresh can retain extra stat-dirty paths in the
        # name-only query above; binding those bytes is conservative. External
        # index writes, including the actual provider's, still revoke authority.
        diff = command(self.root, self.env, "-c", "diff.autoRefreshIndex=false", "-c", "core.quotePath=false",
                       "diff", "--no-color", "-U0", "--relative", "HEAD", "--")
        untracked = command(self.root, self.env, "ls-files", "--others", "--exclude-standard", "-z")
        names(untracked)
        return {"diff": digest(diff), "untracked": digest(untracked)}

    @property
    def statistics(self):
        totals = {}
        for guard in self.guards:
            for name, value in getattr(guard, "statistics", {}).items():
                totals[name] = totals.get(name, 0) + value
        return totals

    def events_unchanged(self):
        """Retained event history only; call unchanged() before publication."""
        return self.watcher.drain() and all(guard.events_unchanged() for guard in self.guards)

    def unchanged(self):
        return (self.watcher.drain() and all(guard.unchanged() for guard in self.guards)
                and self._semantic() == {name: self.identity[name] for name in ("diff", "untracked")})


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
