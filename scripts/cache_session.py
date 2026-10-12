#!/usr/bin/env python3
"""Foreground JSONL developer coordinator session; no daemon or persisted proof.

Requests are {"id": ..., "command": "verify"|"fuzz"|"perf", "args": [...]},
or {"id": ..., "command": "reset"|"stop"}. All command output goes to stderr;
stdout contains one bounded completion per accepted line. Environment and repository
root belong to startup, not requests. A runtime mutation requires process restart.
Python's initial startup runtime is trusted, as in the one-shot coordinators;
bootstrap guards detect later changes. Coordinators and helpers must be imported
under these guards rather than inherited from startup hooks.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib
import importlib.machinery
import json
import marshal
import os
from pathlib import Path
import sys
import sysconfig

import verification_snapshot
from verification_snapshot import RetainedSession, Snapshot, SnapshotError

_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()
_LOADED_FILENAME = sys._getframe().f_code.co_filename
ROOT = Path(__file__).resolve().parents[1]
MAX_LINE = 65536
MAX_ARGS = 256
MAX_ARG = 4096
MAX_ID = 256
COMMANDS = {"verify": "verify_cache", "fuzz": "fuzz_campaign", "perf": "juice_cache"}
DISPATCH_MODULES = frozenset((*COMMANDS.values(), "fuzz_campaign_identity",
                            "fuzz_campaign_store", "verification_artifacts",
                            "verification_process", "verification_report", "verification_budgets",
                            "verification_producers", "verification_telemetry", "verification_policy", "verification_profiles",
                            "juice_evidence", "juice_provider", "juice_worker", "juice_tool"))


class RestartRequired(RuntimeError):
    """The startup runtime no longer certifies loaded coordinator code."""


def request(line: bytes) -> dict:
    if len(line) > MAX_LINE:
        raise ValueError("request exceeds line bound")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate request field")
            result[key] = value
        return result
    value = json.loads(line, object_pairs_hook=unique)
    if type(value) is not dict or set(value) - {"id", "command", "args"}:
        raise ValueError("expected id, command and optional args")
    identifier = value.get("id")
    if type(identifier) not in (str, int) or len(str(identifier)) > MAX_ID:
        raise ValueError("id must be a bounded string or integer")
    command = value.get("command")
    if command not in (*COMMANDS, "reset", "stop"):
        raise ValueError("unsupported command")
    args = value.get("args", [])
    if type(args) is not list or len(args) > MAX_ARGS:
        raise ValueError("args must be a bounded string list")
    if any(type(arg) is not str or len(arg) > MAX_ARG or "\0" in arg for arg in args):
        raise ValueError("invalid argument")
    if command in ("reset", "stop") and args:
        raise ValueError("control requests take no arguments")
    if any(arg.startswith('--') and len(arg.split('=', 1)[0]) > 2
           and any(private.startswith(arg.split('=', 1)[0]) for private in ('--worker', '--admitted'))
           for arg in args):
        raise ValueError("private coordinator modes are forbidden")
    return {"id": identifier, "command": command, "args": args}


@contextmanager
def command_output():
    """Redirect descriptor 1 too, including output from inherited subprocesses."""
    sys.stdout.flush()
    saved = os.dup(1)
    try:
        os.dup2(2, 1)
        yield
    finally:
        sys.stdout.flush()
        os.dup2(saved, 1)
        os.close(saved)


class _SourceLoader(importlib.machinery.SourceFileLoader):
    def get_code(self, fullname):
        # Timestamp-qualified pyc is insufficient for a guarded persistent host.
        return self.source_to_code(self.get_data(self.path), self.path)


class _GuardedFinder:
    def find_spec(self, fullname, path=None, target=None):
        spec = importlib.machinery.PathFinder.find_spec(fullname, path, target)
        if spec is not None and isinstance(spec.loader, importlib.machinery.SourceFileLoader):
            spec.loader = _SourceLoader(fullname, spec.loader.path)
        return spec


class RuntimeGuard:
    """Independent watch authority established before coordinator imports.

    The complete stdlib source/provider tree excludes installed third party
    packages. Loaded external providers are bound separately, and new unbound
    imports reject certification. This guard is never admitted to the warm pool.
    """
    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.snapshot = None
        self.providers = set()
        self.finder = _GuardedFinder()
        self.library_snapshot = None
        self._libraries = set()
        self._runtime_sealed = False

    @staticmethod
    def _mapped_libraries():
        """Executable file mappings bind live inode/device, including deleted libs."""
        result = set()
        with open('/proc/self/maps', encoding='utf-8') as stream:
            for line in stream:
                fields = line.rstrip('\n').split(None, 5)
                if len(fields) != 6 or 'x' not in fields[1] or not fields[5].startswith('/'):
                    continue
                path = Path(fields[5])
                try:
                    metadata = path.stat()
                except OSError as error:
                    raise RestartRequired('loaded runtime library vanished: ' + str(path)) from error
                major, minor = (int(value, 16) for value in fields[3].split(':'))
                if (metadata.st_ino != int(fields[4]) or os.major(metadata.st_dev) != major
                        or os.minor(metadata.st_dev) != minor):
                    raise RestartRequired('loaded runtime library was replaced: ' + str(path))
                result.add(path)
        return result

    def seal_runtime(self):
        """Bind post-import dependencies once, then forbid new unguarded loads."""
        current = self._mapped_libraries()
        extra = current - self._libraries
        if extra:
            self.library_snapshot = Snapshot(self.root, [], sorted(extra))
            self.library_snapshot.__enter__()
        self._libraries = current
        self._runtime_sealed = True
        self.check()

    def __enter__(self):
        preloaded = sorted(name for name in sys.modules
                           if name.split('.', 1)[0] in DISPATCH_MODULES)
        if preloaded:
            raise RestartRequired("coordinator/helper was loaded before bootstrap: " + preloaded[0])
        stdlib = Path(sysconfig.get_path("stdlib"))
        self._libraries = self._mapped_libraries()
        providers = {Path(sys.executable).absolute(), Path('/proc/self/exe').resolve(), *self._libraries}
        directories = []
        for base, names, files in os.walk(stdlib):
            names[:] = [name for name in names if name not in
                        ("site-packages", "dist-packages", "__pycache__") and not name.startswith('.')]
            directories.append(Path(base))
            providers.update(Path(base) / name for name in files if name.endswith((".py", ".so")))
        for module in tuple(sys.modules.values()):
            path = self._provider(module)
            if path is not None and path.is_file():
                providers.add(path)
        self.providers = {path.resolve() for path in providers}
        self.snapshot = Snapshot(self.root, ["scripts/**/*.py"], sorted(providers),
                                 directory_membership=directories)
        self.snapshot.__enter__()
        try:
            self.providers.update((self.root / row['path']).resolve()
                                  for row in self.snapshot.identity['files'])
            self._compiled(verification_snapshot, verification_snapshot._LOADED_CODE_OBJECT,
                           verification_snapshot.__file__)
            self._compiled(sys.modules[__name__], _LOADED_CODE_OBJECT, _LOADED_FILENAME)
            self.check()
            sys.meta_path.insert(0, self.finder)
            return self
        except BaseException:
            self.snapshot.close()
            raise

    @staticmethod
    def _provider(module):
        filename = getattr(module, '__file__', None)
        if not filename:
            return None
        if filename.endswith(('.pyc', '.pyo')):
            try:
                filename = importlib.util.source_from_cache(filename)
            except ValueError:
                pass
        return Path(filename).absolute()

    @staticmethod
    def _compiled(module, expected, filename):
        source = Path(module.__file__).read_bytes()
        code = compile(source, filename, 'exec', dont_inherit=True, optimize=sys.flags.optimize)
        if code != expected:
            raise RestartRequired("loaded bootstrap source does not match guarded bytes")

    def check(self):
        try:
            if not self.snapshot.unchanged():
                reasons = self.snapshot.stability_diagnostics("session_runtime")
                raise RestartRequired("startup runtime changed; restart required: " +
                                      json.dumps(reasons, ensure_ascii=True, separators=(',', ':'))[:768])
            if self.library_snapshot is not None and not self.library_snapshot.unchanged():
                reasons = self.library_snapshot.stability_diagnostics("session_libraries")
                raise RestartRequired("loaded libraries changed; restart required: " +
                                      json.dumps(reasons, ensure_ascii=True, separators=(',', ':'))[:768])
        except SnapshotError as error:
            raise RestartRequired("startup watcher lost; restart required: " + str(error)) from error
        if self._runtime_sealed and self._mapped_libraries() - self._libraries:
            raise RestartRequired("new unguarded loaded runtime library; restart required")
        for module in tuple(sys.modules.values()):
            path = self._provider(module)
            if path is not None and path.resolve() not in self.providers:
                raise RestartRequired("unguarded runtime provider: " + str(path))

    def __exit__(self, *_args):
        if self.finder in sys.meta_path:
            sys.meta_path.remove(self.finder)
        if self.snapshot is not None:
            self.snapshot.close()
        if self.library_snapshot is not None:
            self.library_snapshot.close()


def load_dispatch(guard):
    result = {}
    for command, module_name in COMMANDS.items():
        module = importlib.import_module(module_name)
        guard.check()
        result[command] = module.main
    guard.seal_runtime()
    return result


def serve(stream, output, dispatch, session, guard):
    """Sequential bounded requests; completion status comes from real dispatch."""
    while True:
        line = stream.readline(MAX_LINE + 1)
        if not line:
            return 0
        value = None
        status = 2
        message = None
        stop = False
        restart = False
        before = session.statistics
        try:
            # An oversized line is a protocol failure, not multiple requests.
            if len(line) > MAX_LINE:
                raise RestartRequired("request line bound exceeded; restart required")
            value = request(line)
            guard.check()
            if value['command'] == 'stop':
                status, stop = 0, True
            elif value['command'] == 'reset':
                session.reset()
                status = 0
            else:
                with session.activate(), command_output():
                    try:
                        status = dispatch[value['command']](value['args'])
                    except SystemExit as error:
                        status = error.code if type(error.code) is int else (0 if error.code is None else 2)
                if type(status) is not int or not 0 <= status <= 255:
                    status = 2
                    message = 'coordinator returned an invalid status'
            guard.check()
            if status in (129, 130, 143):
                stop = True
                message = 'request cancelled; session stopped'
        except RestartRequired as error:
            status, message, stop, restart = 75, str(error), True, True
        except (KeyboardInterrupt, InterruptedError):
            status, message, stop = 130, 'request cancelled; session stopped', True
        except Exception as error:
            status, message = 2, str(error)
            # A failed command cannot hide simultaneous runtime mutation.
            try:
                guard.check()
            except RestartRequired as changed:
                status, message, stop, restart = 75, str(changed), True, True
        completion = {"id": value['id'] if value else None, "status": status,
                      "ok": status == 0, "restart_required": restart,
                      "snapshot_work": {key: value - before[key]
                                        for key, value in session.statistics.items()}}
        if message:
            completion['error'] = message[:1024]
        output.write(json.dumps(completion, ensure_ascii=True, separators=(',', ':')) + '\n')
        output.flush()
        if stop:
            return status


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--max-snapshots', '--maxSnapshots', type=int, default=16)
    parser.add_argument('--max-entries', '--maxEntries', type=int, default=262144)
    args = parser.parse_args(argv)
    sys.dont_write_bytecode = True
    os.chdir(ROOT)
    startup_environment = dict(os.environ)
    try:
        with RetainedSession(args.max_snapshots, args.max_entries) as session, RuntimeGuard() as guard:
            with command_output():
                dispatch = load_dispatch(guard)
            # Requests have no cwd/env controls. Restore any coordinator mutation
            # before the next request through the dispatch wrapper.
            def fixed(command):
                def run(options):
                    os.chdir(ROOT)
                    os.environ.clear()
                    os.environ.update(startup_environment)
                    try:
                        return command(options)
                    finally:
                        os.chdir(ROOT)
                        os.environ.clear()
                        os.environ.update(startup_environment)
                return run
            return serve(sys.stdin.buffer, sys.stdout,
                         {name: fixed(command) for name, command in dispatch.items()}, session, guard)
    except (RestartRequired, SnapshotError, ValueError, OSError) as error:
        print('cache-session: ' + str(error), file=sys.stderr)
        return 75
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
