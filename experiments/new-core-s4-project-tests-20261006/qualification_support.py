"""Local S4 qualification receipts and process ownership; historical tools stay frozen."""
import ctypes
import errno
import hashlib
import json
import locale
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
import time


def identity(path, executable=False):
    path = Path(path).resolve(strict=True)
    if not path.is_file() or (executable and not os.access(path, os.X_OK)):
        raise ValueError(f"expected {'executable ' if executable else ''}file: {path}")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"path": str(path), "sha256": digest}


def distinct_oracles(old, core):
    values = {"old": identity(old, True), "core": identity(core, True)}
    if os.path.samefile(old, core) or values["old"]["sha256"] == values["core"]["sha256"]:
        raise ValueError("old and Core must be distinct compiler binaries")
    return values


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def receipt_arguments(parser):
    parser.add_argument("--old-source", required=True, help="Git source revision of the immutable old compiler")
    parser.add_argument("--core-source", required=True, help="Git source revision of the immutable Core compiler")
    parser.add_argument("--zig", type=Path, help="Pinned Zig executable; defaults to MYLANG_ZIG, then PATH")
    parser.add_argument("--qbe", type=Path, help="Pinned QBE executable; defaults to MYLANG_QBE, then PATH")


def tool(value, variable, name):
    chosen = str(value) if value else os.environ.get(variable) or shutil.which(name)
    if not chosen:
        raise ValueError(f"set --{name} or {variable} to the pinned executable")
    return identity(chosen, True)


def manifest(root, old, core, args, sources, extra_tools=()):
    oracles = distinct_oracles(old, core)
    tools = {"python": identity(sys.executable, True),
             "zig": tool(args.zig, "MYLANG_ZIG", "zig"),
             "qbe": tool(args.qbe, "MYLANG_QBE", "qbe")}
    for name in extra_tools:
        path = shutil.which(name)
        if not path:
            raise ValueError(f"required tool is unavailable: {name}")
        tools[name] = identity(path, True)
    # Every compiler child uses the recorded tools, including the copied old oracle.
    os.environ.update(MYLANG_ZIG=tools["zig"]["path"], MYLANG_QBE=tools["qbe"]["path"])
    return {"source_commit": git(root, "rev-parse", "HEAD"), "oracles": oracles,
            "compiler_sources": {"old": git(root, "rev-parse", "--verify", args.old_source + "^{commit}"),
                                 "core": git(root, "rev-parse", "--verify", args.core_source + "^{commit}")},
            "tools": tools, "harnesses": [identity(path) for path in sorted(set(map(Path, sources)))],
            "tool_environment": {key: os.environ[key] for key in ("MYLANG_ZIG", "MYLANG_QBE")}}


def unchanged(root, receipt):
    files = [*receipt["oracles"].values(), *receipt["tools"].values(), *receipt["harnesses"]]
    try:
        return (git(root, "rev-parse", "HEAD") == receipt["source_commit"]
                and not git(root, "status", "--porcelain", "--untracked-files=no")
                and all(os.environ.get(key) == value for key, value in receipt["tool_environment"].items())
                and all(os.access(item["path"], os.X_OK) for item in [*receipt["oracles"].values(), *receipt["tools"].values()])
                and all(identity(item["path"]) == item for item in files))
    except (OSError, ValueError, subprocess.SubprocessError):
        return False


def snapshot(folder, destination):
    """Retain exact input bytes before mutation, separately from the executable project."""
    destination.mkdir(parents=True, exist_ok=False)
    files = {}
    for path in sorted(folder.rglob("*")):
        if path.is_file():
            relative = path.relative_to(folder)
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
            files[str(relative)] = identity(target)
    (destination / "snapshot.json").write_text(json.dumps(files, indent=2) + "\n")
    return {"directory": str(destination), "files": files}


_subreaper_lock = threading.Lock()
_subreaper_ready = False


def subreaper():
    """Adopt killed command descendants so they are reaped instead of left as zombies."""
    global _subreaper_ready
    with _subreaper_lock:
        if not _subreaper_ready:
            libc = ctypes.CDLL(None, use_errno=True)
            if libc.prctl(36, 1, 0, 0, 0) != 0:  # Linux PR_SET_CHILD_SUBREAPER.
                raise OSError(ctypes.get_errno(), "cannot enable qualification child subreaper")
            _subreaper_ready = True


def reap_group(group):
    while True:
        try:
            os.waitpid(-group, 0)
        except ChildProcessError:
            return
        except OSError as error:
            if error.errno != errno.EINTR:
                raise


def kill_tree(root):
    """Stop forks before walking descendants, including nested capture sessions."""
    owned, pending = set(), [root]
    while pending:
        pid = pending.pop()
        if pid in owned:
            continue
        try:
            os.kill(pid, signal.SIGSTOP)
        except ProcessLookupError:
            continue
        owned.add(pid)
        for task in Path(f"/proc/{pid}/task").glob("*/children"):
            try:
                pending.extend(map(int, task.read_text().split()))
            except FileNotFoundError:
                pass
    try:
        os.killpg(root, signal.SIGKILL)
    except ProcessLookupError:
        pass
    for pid in owned:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return owned - {root}


def reap_children(children):
    for pid in children:
        while True:
            try:
                os.waitpid(pid, 0)
                break
            except ChildProcessError:
                break
            except OSError as error:
                if error.errno != errno.EINTR:
                    raise


def child_pids():
    children = set()
    for path in Path(f"/proc/{os.getpid()}/task").glob("*/children"):
        children.update(map(int, path.read_text().split()))
    return children


def clean_supervisor_children(exclude_reap=()):
    """This process owns only one command, including all its adopted orphans."""
    first = True
    while first or child_pids() - set(exclude_reap):
        first = False
        owned = set()
        for pid in child_pids():
            owned.add(pid)
            owned.update(kill_tree(pid))
        reap_children(owned - set(exclude_reap))


def supervise(job_path):
    """A dedicated subreaper keeps ancestry after the original command exits."""
    job = json.loads(Path(job_path).read_text())
    stem = Path(job["stem"])
    subreaper()
    stdout, stderr, timed_out, status, error = b"", b"", False, None, None
    began, process = time.monotonic(), None
    try:
        options = job["options"]
        data = sys.stdin.buffer.read() if job["input"] else None
        if job["input"]:
            options["stdin"] = subprocess.PIPE
        process = subprocess.Popen(job["argv"], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT if job["merged_stderr"] else subprocess.PIPE,
            start_new_session=True, **options)
        try:
            stdout, stderr = process.communicate(data, timeout=job["timeout"])
        except subprocess.TimeoutExpired:
            timed_out = True
            # The original child may be gone. Orphans still belong to this
            # isolated supervisor, never another concurrent command.
            clean_supervisor_children({process.pid})
            stdout, stderr = process.communicate()
        status = process.returncode
    except Exception as failure:
        error = f"{type(failure).__name__}: {failure}"
    finally:
        clean_supervisor_children({process.pid} if process is not None else ())
        if process is not None:
            process.wait()
        clean_supervisor_children()
        stem.with_suffix(".stdout").write_bytes(stdout or b"")
        stem.with_suffix(".stderr").write_bytes(stderr or b"")
        stem.with_suffix(".result.json").write_text(json.dumps({
            "status": status, "timed_out": timed_out, "error": error,
            "seconds": time.monotonic() - began, "supervisor": os.getpid(),
            "remaining_children": sorted(child_pids())}, indent=2) + "\n")
    return 0 if error is None else 125


class Capture:
    """subprocess.run-compatible local capture, with raw receipts even on timeout."""
    def __init__(self, directory, cwd):
        self.directory, self.cwd = Path(directory), cwd
        self.directory.mkdir(parents=True, exist_ok=False)
        self.lock, self.sequence = threading.Lock(), 0

    def run(self, argv, *positional, **options):
        if positional:
            raise ValueError("qualification capture requires keyword process options")
        capture = options.pop("capture_output", False)
        out, err = options.pop("stdout", None), options.pop("stderr", None)
        if capture and (out is not None or err is not None):
            raise ValueError("capture_output conflicts with stdout/stderr")
        if capture:
            out = err = subprocess.PIPE
        text = options.pop("text", False) or options.pop("universal_newlines", False)
        encoding, errors = options.pop("encoding", None), options.pop("errors", None)
        text = text or encoding is not None or errors is not None
        codec = encoding or locale.getpreferredencoding(False)
        timeout, check = options.pop("timeout", None), options.pop("check", False)
        data = options.pop("input", None)
        if isinstance(data, str):
            data = data.encode(codec, errors or "strict")
        if data is not None:
            if options.get("stdin") is not None:
                raise ValueError("input conflicts with stdin")
            options["stdin"] = subprocess.PIPE
        options["cwd"] = str(options.get("cwd") or self.cwd)
        options.pop("start_new_session", None)
        environment = options.pop("env", None)
        stdin = options.pop("stdin", None)
        input_pipe = stdin == subprocess.PIPE
        subreaper()
        with self.lock:
            self.sequence += 1
            stem = self.directory / f"command-{self.sequence:05}"
        command = argv if isinstance(argv, str) else [os.fspath(value) for value in argv]
        job_path = stem.with_suffix(".job.json")
        job_path.write_text(json.dumps({"argv": command, "options": options,
            "input": input_pipe, "merged_stderr": err == subprocess.STDOUT,
            "timeout": timeout, "stem": str(stem)}) + "\n")
        supervisor = [sys.executable, str(Path(__file__).resolve()), "--supervise", str(job_path)]
        began, forced_timeout = time.monotonic(), False
        with subprocess.Popen(supervisor, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              stdin=stdin, cwd=options["cwd"], env=environment,
                              pass_fds=options.get("pass_fds", ()), start_new_session=True) as process:
            try:
                supervisor_out, supervisor_err = process.communicate(data, timeout=None if timeout is None else timeout + 5)
            except subprocess.TimeoutExpired:
                forced_timeout = True
                children = kill_tree(process.pid)
                supervisor_out, supervisor_err = process.communicate()
                reap_group(process.pid)
                reap_children(children)
            supervisor_status = process.returncode
        stem.with_suffix(".supervisor.stdout").write_bytes(supervisor_out or b"")
        stem.with_suffix(".supervisor.stderr").write_bytes(supervisor_err or b"")
        result_path = stem.with_suffix(".result.json")
        completed = json.loads(result_path.read_text()) if result_path.exists() else {
            "status": None, "timed_out": forced_timeout, "error": "supervisor did not complete"}
        stdout = stem.with_suffix(".stdout").read_bytes() if stem.with_suffix(".stdout").exists() else b""
        stderr = stem.with_suffix(".stderr").read_bytes() if stem.with_suffix(".stderr").exists() else b""
        for suffix, value in (("stdout", stdout), ("stderr", stderr)):
            stem.with_suffix("." + suffix).write_bytes(value)
        timed_out, status = forced_timeout or completed["timed_out"], completed["status"]
        receipt = {"argv": argv, "cwd": str(options["cwd"]), "status": status,
                   "timed_out": timed_out, "timeout": timeout, "seconds": time.monotonic() - began,
                   "supervisor": supervisor, "supervisor_status": supervisor_status,
                   "supervisor_result": completed,
                   "environment": {key: value for key, value in (environment if environment is not None else os.environ).items()
                                   if key in ("MYLANG_ZIG", "MYLANG_QBE", "MYL_CORE_LEAKCHECK", "TMPDIR", "ZIG_LOCAL_CACHE_DIR", "ZIG_GLOBAL_CACHE_DIR")},
                   "stdout": identity(stem.with_suffix(".stdout")),
                   "stderr": identity(stem.with_suffix(".stderr"))}
        stem.with_suffix(".json").write_text(json.dumps(receipt, indent=2) + "\n")

        def delivered(value, stream, default):
            if stream == subprocess.PIPE:
                return value.decode(codec, errors or "strict").replace("\r\n", "\n").replace("\r", "\n") if text else value
            if stream not in (subprocess.DEVNULL, subprocess.STDOUT):
                target = stream if stream is not None else default
                if isinstance(target, int):
                    os.write(target, value)
                else:
                    try:
                        target.write(value)
                    except TypeError:
                        target.write(value.decode(codec, errors or "replace"))
                    target.flush()
            return None

        if timed_out:
            # Match subprocess: TimeoutExpired carries raw bytes even with text=True.
            raise subprocess.TimeoutExpired(argv, timeout, output=stdout, stderr=stderr)
        if supervisor_status != 0 or completed["error"] is not None or completed.get("remaining_children"):
            raise OSError(f"qualification supervisor failed: {completed}")
        result = subprocess.CompletedProcess(argv, status,
            delivered(stdout, out, getattr(sys.stdout, "buffer", sys.stdout)),
            delivered(stderr, err, getattr(sys.stderr, "buffer", sys.stderr)))
        if check and status:
            raise subprocess.CalledProcessError(status, argv, output=result.stdout, stderr=result.stderr)
        return result


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "--supervise":
        raise SystemExit("qualification_support.py is a local capture helper")
    raise SystemExit(supervise(sys.argv[2]))
