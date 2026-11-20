#!/usr/bin/env python3
"""Refresh a registered, detached timer worktree and serialize its service runs."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import threading
import time

RUNNERS = {
    "core": "scripts/systemd/core-store-maintenance.sh",
    "nightly": "scripts/nightly-integration.sh",
}
MARKER = "selka-service-worktree.json"
# How long the wrapper stays alive after its last line, in seconds. journald names a line's unit from the cgroup of the
# process that wrote it, read when it handles the line: a process gone by then leaves the line in the journal with no
# unit, and `journalctl -u` does not show it (the nightly's verdict line of 15 November was only in `journalctl --user`).
SETTLE_SECONDS = 3.0
# How long the wrapper waits, after its runner has ended, for the runner's standard output to close: a background process
# the runner left holding it must not keep the service from ending.
RELAY_DRAIN_SECONDS = 10.0


def git(root, *arguments, check=True):
    return subprocess.run(["git", "-C", str(root), *arguments], check=check,
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def detached_clean(root):
    """Never detach a developer branch or discard tracked/untracked changes."""
    if Path(git(root, "rev-parse", "--show-toplevel").stdout.strip()).resolve() != root:
        raise ValueError("service worktree must be the repository top level")
    branch = git(root, "symbolic-ref", "-q", "HEAD", check=False)
    if branch.returncode != 1:
        raise ValueError("service worktree must already be detached")
    if git(root, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none").stdout:
        raise ValueError("refusing to refresh a dirty service worktree")


def marker_path(root):
    return Path(git(root, "rev-parse", "--path-format=absolute", "--git-path", MARKER).stdout.strip())


def register(root):
    """Installers register only the clean detached checkout selected by the user."""
    root = Path(root).resolve(strict=True)
    detached_clean(root)
    marker = marker_path(root)
    if marker.is_symlink():
        raise ValueError("service registration may not be a symlink")
    with tempfile.NamedTemporaryFile(mode="w", dir=marker.parent, prefix=MARKER + ".", delete=False) as output:
        temporary = Path(output.name)
        json.dump({"version": 1, "worktree": str(root)}, output)
        output.write("\n")
    try:
        temporary.replace(marker)
    finally:
        temporary.unlink(missing_ok=True)


def require_registered(root):
    marker = marker_path(root)
    if marker.is_symlink() or not marker.is_file():
        raise ValueError("worktree is not registered by a service installer")
    if json.loads(marker.read_text()) != {"version": 1, "worktree": str(root)}:
        raise ValueError("service registration does not match this worktree")


def run(root, service, arguments=()):
    try:
        root = Path(root).resolve(strict=True)
    except FileNotFoundError:
        raise ValueError(f"service checkout {root} is missing; reinstall the timer from an existing checkout")
    require_registered(root)
    common = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    descriptor = os.open(common / "mylang-services.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)  # rename: keep: the lease every checkout of this repository shares, old scripts and new
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError("service lock is not a regular file")
        # Both timers use this permanent inode. Keep it through the refreshed
        # child, not merely through checkout; a second timer must not replace
        # files that the first service is still reading.
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        require_registered(root)
        detached_clean(root)
        git(root, "checkout", "--detach", "main")
        commit = git(root, "rev-parse", "HEAD").stdout.strip()
        runner = RUNNERS[service]
        git(root, "ls-files", "--error-unmatch", "--", runner)
        detached_clean(root)
        print(f"service={service} worktree={root} commit={commit}", flush=True)
        # The child inherits the lease too, so terminating only the Python
        # supervisor cannot release it while the shell remains alive.
        # The runner's standard output is relayed line by line by this process, which has been alive all run: its own
        # lines show under the unit, a line written by a runner that exits at once does not (see SETTLE_SECONDS).
        relayed = []

        def relay(stream):
            for line in stream:
                print(line, end="", flush=True)
                relayed.append(line)

        # Not a `with` block: closing the pipe waits for a reader that is blocked on it, which is what a background
        # process holding it makes the reader be. The reader is a daemon thread, and this process exits soon after.
        child = subprocess.Popen(["/usr/bin/bash", str(root / runner), *arguments], cwd=root, pass_fds=(descriptor,),
                                 stdout=subprocess.PIPE, text=True, errors="replace")
        reader = threading.Thread(target=relay, args=(child.stdout,), daemon=True)
        reader.start()
        child.wait()
        reader.join(timeout=float(os.environ.get("SELKA_SERVICE_RELAY_DRAIN_SECONDS", RELAY_DRAIN_SECONDS)))
        returncode = child.returncode
        if relayed:
            time.sleep(float(os.environ.get("SELKA_SERVICE_SETTLE_SECONDS", SETTLE_SECONDS)))
        return returncode if returncode >= 0 else 128 - returncode
    finally:
        os.close(descriptor)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worktree", type=Path, required=True)
    parser.add_argument("--service", choices=RUNNERS, required=True)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args(argv)
    arguments = options.arguments[1:] if options.arguments[:1] == ["--"] else options.arguments
    try:
        return run(options.worktree, options.service, arguments)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"service-worktree: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
