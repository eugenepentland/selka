#!/usr/bin/env python3
"""Repeat the useful hashing configurations without perf instrumentation."""
import fcntl
import json
from pathlib import Path
from build_hashes import HERE, ROOT, TOOLS, WORK
from measure import once

rows = []
expected = None
names = ['pinned-baseline', 'pinned-safe-native', 'release-native']
with Path('/run/user/1000/mylang-slots/cpu2.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    for rep in range(4):
        for name in (names if rep % 2 == 0 else list(reversed(names))):
            command = [WORK / 'coordinators' / name, '--root', ROOT, '--zig', TOOLS['pinned'],
                       '--cache-dir', '/home/epentland/.cache/mylang/components', '--seed-only']
            row, output = once(name, command, rep, 'coordinator-followup')
            if expected is None:
                expected = output
            assert output == expected, name
            rows.append(row)
            (HERE / 'coordinator-followup.json').write_text(json.dumps(rows, indent=2) + '\n')
            print(name, rep, row['wall_s'], flush=True)
