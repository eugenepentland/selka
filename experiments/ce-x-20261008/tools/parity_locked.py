#!/usr/bin/env python3
"""bench_parity.py, unchanged, except that the CPU-10 lock is taken only for the timing.

The first time the harness pins itself to the timing CPU (`Pinned(cpu)`, the timing and
confirmation passes), this wrapper takes `flock /run/user/1000/mylang-slots/cpu10.lock`
and holds it until the process exits. The build phase (`OffTimingCpus`) and the output
qualification run before that, without the lock, so no build runs while the lock is held.
usage: parity_locked.py run ARGS...   (the arguments of `bench_parity.py`)
"""
import fcntl, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "bench/parity"))
import bench_parity as bp

LOCK = "/run/user/1000/mylang-slots/cpu10.lock"
held = []
original = bp.Pinned.__enter__


def enter(self):
    if self.cpu >= 0 and not held:
        handle = open(LOCK, "a")
        started = time.monotonic()
        fcntl.flock(handle, fcntl.LOCK_EX)
        held.append(handle)
        print(f"parity_locked: took {LOCK} after {time.monotonic() - started:.1f} s", file=sys.stderr, flush=True)
    return original(self)


bp.Pinned.__enter__ = enter
if __name__ == "__main__":
    sys.exit(bp.main())
