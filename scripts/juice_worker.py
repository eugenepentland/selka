#!/usr/bin/env python3
"""Private Linux admitted worker: supervise and reap the entire native process tree.

Usage: python3 juice_worker.py NATIVE_ARGS...
The native exit status is preserved; signal exits use 128+signal. Setup or
incomplete bounded cleanup returns 125, and missing arguments return 2.
Subreaping keeps separate process groups/sessions owned until cleanup finishes.
"""
import ctypes
import errno
import hashlib
import verification_code_identity as code_identity
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
CLEANUP_SECONDS = 5.0
TERM_SECONDS = 0.35
POLL_SECONDS = 0.02
CHILDREN_READ_BYTES = 1024 * 1024
REAP_LIMIT = 512
_CANCELLED = 0


def _cancel_signal(signum, _frame):
    global _CANCELLED
    if not _CANCELLED:
        _CANCELLED = signum


def _subreaper():
    if not sys.platform.startswith('linux') or not hasattr(os, 'pidfd_open') or not hasattr(signal, 'pidfd_send_signal'):
        raise OSError('Linux subreaping and pidfd signaling are required')
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                          ctypes.c_ulong, ctypes.c_ulong]
    libc.prctl.restype = ctypes.c_int
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        failure = ctypes.get_errno()
        raise OSError(failure, os.strerror(failure))


def _children():
    # This private supervisor has one thread. Only kernel-maintained direct
    # children are eligible; descendants become direct adoptees as parents die.
    path = Path('/proc/self/task') / str(os.getpid()) / 'children'
    with path.open('rb') as stream:
        data = stream.read(CHILDREN_READ_BYTES + 1)
    if len(data) > CHILDREN_READ_BYTES:
        # Kill/reap a bounded prefix, then discover the remaining children on the
        # next pass. Do not interpret a truncated numeric PID at the boundary.
        data = data[:CHILDREN_READ_BYTES].rsplit(b' ', 1)[0]
    return [int(value) for value in data.split()]


def _parent(pid):
    try:
        with open(f'/proc/{pid}/stat', 'rb') as stream:
            data = stream.read(4096)
        # comm is parenthesized and may itself contain spaces or parentheses.
        return int(data.rsplit(b') ', 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return None


def _signal_owned(pid, signum):
    """Anchor a child with a pidfd, then check ownership before signaling."""
    descriptor = None
    try:
        descriptor = os.pidfd_open(pid, 0)
        if _parent(pid) == os.getpid():
            signal.pidfd_send_signal(descriptor, signum)
    except OSError as error:
        if error.errno not in (errno.ESRCH, errno.ENOENT):
            raise
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _reap(root, deadline=None):
    for _ in range(REAP_LIMIT):
        if deadline is not None and time.monotonic() >= deadline:
            return
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        except InterruptedError:
            continue
        if pid == 0:
            return
        if root is not None and pid == root.pid:
            root.returncode = os.waitstatus_to_exitcode(status)


def _cleanup(root):
    """Terminate and reap only direct/adopted children, within five seconds."""
    started = time.monotonic()
    deadline = started + CLEANUP_SECONDS
    while True:
        _reap(root, deadline)
        children = _children()
        if not children:
            return True
        now = time.monotonic()
        if now >= deadline:
            return False
        signum = signal.SIGTERM if now < started + TERM_SECONDS else signal.SIGKILL
        for pid in children:
            if time.monotonic() >= deadline:
                return False
            _signal_owned(pid, signum)
        time.sleep(min(POLL_SECONDS, max(0, deadline - time.monotonic())))


def run(argv):
    """Execute native argv under subreaping; admission ends only after cleanup."""
    if not argv:
        print('usage: juice_worker.py NATIVE_ARGS...', file=sys.stderr)
        return 2
    root = None
    status = 125
    try:
        # Install cancellation handlers before all startup work and child spawn.
        for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP, signal.SIGQUIT):
            signal.signal(signum, _cancel_signal)
        _subreaper()
        if not _CANCELLED:
            root = subprocess.Popen(argv, start_new_session=True)
            while not _CANCELLED:
                _reap(root)
                if root.returncode is not None:
                    break
                time.sleep(POLL_SECONDS)
            status = 128 + _CANCELLED if _CANCELLED else root.returncode
            if status is not None and status < 0:
                status = 128 - status
        else:
            status = 128 + _CANCELLED
    except (OSError, ValueError) as error:
        print('juice-worker: cannot supervise native command: ' + str(error), file=sys.stderr)
    finally:
        try:
            clean = _cleanup(root)
        except (OSError, ValueError) as error:
            print('juice-worker: descendant cleanup failed: ' + str(error), file=sys.stderr)
            clean = False
        if not clean:
            print('juice-worker: owned descendants remain after bounded cleanup', file=sys.stderr)
            status = 125
    # A signal arriving during normal-completion cleanup still cancels authority.
    if _CANCELLED and status != 125:
        return 128 + _CANCELLED
    return status if status is not None else 125


if __name__ == '__main__':
    sys.exit(run(sys.argv[1:]))
