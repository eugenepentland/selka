"""Content identities and bounded child processes shared by the collectors."""
from __future__ import annotations

import hashlib
import json
import marshal
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time
import sys

LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()


class JuiceError(Exception):
    """An invalid experiment or unavailable measurement; never a passing result."""


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     allow_nan=False).encode()).hexdigest()


def file_hash(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def implementation_id():
    return digest({p.name: file_hash(p) for p in Path(__file__).parent.glob("*.py")})


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")
    temporary.replace(path)


def read_json(path):
    return json.loads(Path(path).read_text())


def executable(name):
    found = shutil.which(str(name))
    if not found:
        raise JuiceError(f"executable unavailable: {name}")
    return str(Path(found).resolve())


def tool_identity(name):
    path = executable(name)
    result = subprocess.run([path, "--version"], capture_output=True, timeout=15)
    return {"path": path, "sha256": file_hash(path),
            "version": (result.stdout + result.stderr).decode(errors="replace").strip()[:4096]}


def expand(argv, values):
    # Replace only documented tokens: application arguments can contain JSON/braces.
    result = []
    for arg in argv:
        for name, value in values.items():
            arg = arg.replace("{" + name + "}", str(value))
        result.append(arg)
    return result


def run(argv, cwd, env, prefix, timeout, cpu=None):
    """Keep raw output on disk and kill the entire process group on timeout."""
    prefix = Path(prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with prefix.with_suffix(".stdout").open("wb") as out, prefix.with_suffix(".stderr").open("wb") as err:
        def affinity():
            if cpu is not None:
                os.sched_setaffinity(0, {cpu})
        process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=out, stderr=err,
                                   stdin=subprocess.DEVNULL, start_new_session=True,
                                   preexec_fn=affinity if cpu is not None else None)
        try:
            process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise JuiceError(f"incomplete run (timeout or interruption): {argv[0]}; logs: {prefix}")
    return {"exit_code": process.returncode, "wall_seconds": time.monotonic() - start,
            "stdout_sha256": file_hash(prefix.with_suffix(".stdout")),
            "stderr_sha256": file_hash(prefix.with_suffix(".stderr"))}


def environment(work, extra):
    """Runtime environment is explicit, with stable private home and scratch paths."""
    for name in ("home", "tmp"):
        (work / name).mkdir(exist_ok=True)
    return {"PATH": os.defpath, "LC_ALL": "C", "LANG": "C", "TZ": "UTC",
            "HOME": str(work / "home"), "TMPDIR": str(work / "tmp"),
            "PWD": str(work), **extra}
