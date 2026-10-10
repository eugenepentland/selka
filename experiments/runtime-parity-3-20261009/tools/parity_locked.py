#!/usr/bin/env python3
"""bench_parity.py, unchanged, except that the CPU-10 lock is taken only for the timing.

The first time the harness pins itself to the timing CPU (`Pinned(cpu)`, the timing and
confirmation passes), this wrapper takes `flock /run/user/1000/mylang-slots/cpu10.lock`
and holds it until the process exits. The build phase (`OffTimingCpus`) and the output
qualification run before that, without the lock, so no build runs while the lock is held.
usage: parity_locked.py run ARGS...   (the arguments of `bench_parity.py`)
"""
import sys
import os
import subprocess
from quiet import quiet
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "bench/parity"))
import bench_parity as bp

# Let the runner verify CPU-10 availability, then pin before its first tool
# probe. Build, output qualification and post-timing processing stay off the
# reserved CPUs; Pinned temporarily selects CPU 10 only after quiet admission.
original_find_rustc = bp.find_rustc


def find_rustc(explicit):
    allowed = os.sched_getaffinity(0) - {2, 3, 10, 11}
    if not allowed:
        raise RuntimeError("no non-reserved CPU is available")
    os.sched_setaffinity(0, allowed)
    return original_find_rustc(explicit)


bp.find_rustc = find_rustc

class SlottedProcesses:
    """Keep each compiler invocation within the shared build admission limit."""
    def run(self, command, *args, **kwargs):
        if isinstance(command, (list, tuple)) and command:
            compiler = Path(str(command[0])).name
            is_build = len(command) > 1 and str(command[1]) in ("build", "build-exe")
            is_build = is_build or (compiler == "rustc" and "--crate-name" in command)
            if is_build:
                command = [str(ROOT / "scripts/build-slot.sh"), "build", *command]
        return subprocess.run(command, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(subprocess, name)


bp.subprocess = SlottedProcesses()

LOCK = "/run/user/1000/mylang-slots/cpu10.lock"
held = []
original = bp.Pinned.__enter__


def enter(self):
    if self.cpu >= 0 and not held:
        guard = quiet()
        guard.__enter__()
        held.append(guard)
    return original(self)


bp.Pinned.__enter__ = enter
if __name__ == "__main__":
    try:
        sys.exit(bp.main())
    finally:
        for guard in reversed(held):
            guard.__exit__(None, None, None)
