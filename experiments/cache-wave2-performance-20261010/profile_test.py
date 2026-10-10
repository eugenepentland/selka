#!/usr/bin/env python3
"""Lightweight timeout smoke checks; launches no compiler or profiling tool."""
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

import profile as profiler


def smoke(parent_exits):
    with tempfile.TemporaryDirectory(prefix='mylang-profile-smoke-') as directory:
        root = Path(directory)
        compiler = root / 'fake-compiler'
        child = "import os,time;from pathlib import Path;Path('child.pid').write_text(str(os.getpid()));time.sleep(60)"
        compiler.write_text(f'#!{sys.executable}\n'
                            'import subprocess,sys,time\n'
                            f'subprocess.Popen([sys.executable,"-c",{child!r}])\n'
                            f'{"sys.exit(0)" if parent_exits else "time.sleep(60)"}\n')
        compiler.chmod(0o700)
        started = time.monotonic()
        try:
            profiler.profile(compiler, root, root / 'cache', root,
                             'fake', 'zlib', 'none', timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise AssertionError('inherited capture pipes should trigger timeout')
        assert time.monotonic() - started < 3, 'group cleanup did not finish promptly'
        pid = int((root / 'child.pid').read_text())
        # Subreaper ownership lets this isolated smoke process reap the orphan
        # and prove its termination rather than accepting a lingering zombie.
        reaped, status = os.waitpid(pid, 0)
        assert reaped == pid and os.WIFSIGNALED(status)
        assert os.WTERMSIG(status) == signal.SIGKILL
        while True:
            try:
                if os.waitpid(-1, os.WNOHANG)[0] == 0:
                    break
            except ChildProcessError:
                break
        print(f'PASS: descendants stopped with parent_exits={parent_exits}')


if __name__ == '__main__':
    # PR_SET_CHILD_SUBREAPER affects only this standalone test process.
    assert ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0
    smoke(False)
    smoke(True)
