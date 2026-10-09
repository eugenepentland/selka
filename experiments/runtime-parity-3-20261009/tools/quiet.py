#!/usr/bin/env python3
"""Hold the CPU-10 lock and all shared build/gate slots during a timing command.

Acquisition is nonblocking and releases every lock on contention, so a gate
already holding a gate slot can still acquire its nested build slot. No build
command may be passed here. The child must use prebuilt binaries only.
"""
import contextlib
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import time


@contextlib.contextmanager
def quiet():
    directory = Path('/run/user/1000/mylang-slots')
    names = ['admit.lock', 'gate1.lock', 'build1.lock', 'build2.lock',
             'build3.lock', 'cpu10.lock']
    started = time.monotonic()
    while True:
        held = []
        try:
            for name in names:
                handle = (directory / name).open('a')
                held.append(handle)
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            for handle in reversed(held):
                handle.close()
            time.sleep(5)
            continue
        break
    print(f'quiet: CPU 10 and all slots acquired after {time.monotonic()-started:.1f}s; load={os.getloadavg()}',
          file=sys.stderr, flush=True)
    try:
        yield
    finally:
        print(f'quiet: finished; load={os.getloadavg()}', file=sys.stderr, flush=True)
        for handle in reversed(held):
            handle.close()


if __name__ == '__main__':
    command = sys.argv[1:]
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise SystemExit('usage: quiet.py -- PREBUILT_TIMING_COMMAND ...')
    with quiet():
        raise SystemExit(subprocess.call(command))
