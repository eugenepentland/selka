"""Phase-level admission for developer harnesses; the shell owns queue policy."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


SLOT = Path(__file__).with_name("build-slot.sh")
MARKERS = ("MYLANG_ADMISSION_DIR", "MYLANG_ADMISSION_KIND")


def slot_directory():
    if os.environ.get("MYLANG_SLOT_DIR"):
        return Path(os.environ["MYLANG_SLOT_DIR"]).resolve()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime and Path(runtime).is_dir():
        return (Path(runtime) / "mylang-slots").resolve()
    return (Path.home() / ".cache/mylang/slots").resolve()


@contextmanager
def admission(kind):
    """Acquire outside measured intervals, then release on completion or failure.

    A pipe keeps the admitted helper alive. Parent death closes it and releases
    the locks too. Reusing an outer admission is allowed, but upgrading a build
    to timing is rejected: that would wait for the caller's own build to finish.
    """
    if kind not in ("build", "gate", "timing"):
        raise ValueError("unknown admission kind: " + kind)
    if os.environ.get("MYLANG_ADMISSION_DIR") == str(slot_directory()):
        outer = os.environ.get("MYLANG_ADMISSION_KIND")
        if outer == "timing" or outer == kind or (outer == "gate" and kind == "build"):
            yield
            return
        raise RuntimeError(f"cannot request {kind} inside {outer}; run this harness directly")
    # A parent killed while still queued must not leave a live timing request
    # blocking ordinary work. Once admitted, closing the pipe releases the lease.
    parent_start = Path(f"/proc/{os.getpid()}/stat").read_text().rsplit(") ", 1)[1].split()[19]
    environment = dict(os.environ, MYLANG_ADMISSION_PARENT_PID=str(os.getpid()),
                       MYLANG_ADMISSION_PARENT_START=parent_start)
    process = subprocess.Popen(
        [str(SLOT), kind, sys.executable, "-B", str(Path(__file__).resolve()), "--hold"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, start_new_session=True,
        env=environment)
    original = os.sched_getaffinity(0)
    markers = {key: os.environ.get(key) for key in MARKERS}
    ready = False
    try:
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(f"{kind} admission failed (exit {process.wait()})")
        identity = json.loads(line)
        os.sched_setaffinity(0, identity["cpus"])
        os.environ.update(identity["markers"])
        ready = True
        yield
    finally:
        os.sched_setaffinity(0, original)
        for key, value in markers.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        process.stdin.close()
        try:
            if not ready and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            status = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            status = process.wait()
        finally:
            process.stdout.close()
        if ready and status != 0 and sys.exc_info()[0] is None:
            raise RuntimeError(f"{kind} admission holder failed (exit {status})")


if __name__ == "__main__":
    if sys.argv[1:] != ["--hold"]:
        raise SystemExit("internal helper: use scripts/build-slot.sh build|gate|timing CMD...")
    print(json.dumps({"cpus": sorted(os.sched_getaffinity(0)),
                      "markers": {key: os.environ[key] for key in MARKERS}}), flush=True)
    sys.stdin.buffer.read()
