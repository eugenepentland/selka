#!/usr/bin/env python3
"""Verify the real qualified-seed hashing path and count AVX/SSE assists."""
import fcntl
import json
from pathlib import Path
import subprocess
from build_hashes import HERE, ROOT, TOOLS, WORK
from measure import once

rows = []
expected = None
with Path('/run/user/1000/mylang-slots/cpu2.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    for name in ['pinned-native', 'release-native', 'pinned-baseline', 'release-baseline', 'custom-native', 'custom-baseline']:
        command = [WORK / 'coordinators' / name, '--root', ROOT, '--zig', TOOLS['pinned'],
                   '--cache-dir', '/home/epentland/.cache/mylang/components', '--seed-only']
        metrics = HERE / ('coordinator-' + name + '.perf')
        wrapped = ['perf', 'stat', '-x', ',', '-e', 'cpu_core/cycles/,cpu_core/instructions/,cpu_core/assists.sse_avx_mix/',
                   '-o', metrics, *command]
        row, output = once(name, wrapped, 1, 'coordinator')
        if expected is None:
            expected = output
        assert output == expected, (name, output, expected)
        row['perf'] = metrics.read_text()
        row['command'] = list(map(str, command))
        rows.append(row)
        (HERE / 'coordinator-measurements.json').write_text(json.dumps(rows, indent=2) + '\n')
        print(name, row['wall_s'], row['rss_kib'], flush=True)
