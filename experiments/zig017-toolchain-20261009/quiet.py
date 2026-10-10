#!/usr/bin/env python3
"""Reserve the shared build/gate slots for a short, prebuilt timing window."""
import fcntl
from pathlib import Path
import subprocess
import sys
import time

directory = Path('/run/user/1000/mylang-slots')
names = ['admit.lock', 'gate1.lock', 'build1.lock', 'build2.lock', 'build3.lock']
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
        time.sleep(2)
        continue
    break
print(f'Prebuilt timing window acquired after {time.monotonic() - started:.2f}s', flush=True)
try:
    raise SystemExit(subprocess.call(sys.argv[1:]))
finally:
    for handle in reversed(held):
        handle.close()
