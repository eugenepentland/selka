#!/usr/bin/env python3
"""Exclude other builds while measuring a core rebuild under the gate lock.

Launch inside build-slot's build wrapper, itself inside its gate wrapper.
That owns one build slot; this helper holds the remaining build-slot locks until
the timed command exits. Waiting for other builds is outside command time.
"""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    command = sys.argv[1:]
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise SystemExit('a timed core-build command is required')
    inherited = Path(os.readlink('/proc/self/fd/9')).resolve()
    if not inherited.name.startswith('build') or inherited.suffix != '.lock':
        raise SystemExit('launch through build-slot.sh build inside the gate wrapper')
    slots = int(os.environ.get('MYLANG_BUILD_SLOTS', '3'))
    held = []
    started = time.monotonic()
    try:
        for index in range(1, slots + 1):
            path = inherited.parent / f'build{index}.lock'
            if path == inherited:
                continue
            lock = path.open('a')
            held.append(lock)
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        print(f'core-exclusive: all {slots} build slots held; other-build wait='
              f'{time.monotonic() - started:.3f}s; gate wrapper excludes gate execution',
              flush=True)
        return subprocess.run(command).returncode
    finally:
        for lock in held:
            lock.close()


if __name__ == '__main__':
    raise SystemExit(main())
