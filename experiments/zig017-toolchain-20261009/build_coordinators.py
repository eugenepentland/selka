#!/usr/bin/env python3
"""Build the real coordinator to reproduce the reported hashing context."""
import json
import os
import subprocess
from build_hashes import HERE, ROOT, TOOLS, WORK

rows = []
for label, tool in TOOLS.items():
    cases = [('native', 'ReleaseFast'), ('baseline', 'ReleaseFast')]
    if label == 'pinned':
        cases.append(('native', 'ReleaseSafe'))
    for cpu, mode in cases:
        name = label + ('-safe-' if mode == 'ReleaseSafe' else '-') + cpu
        output = WORK / 'coordinators' / name
        output.parent.mkdir(parents=True, exist_ok=True)
        command = [str(tool), 'build-exe', str(ROOT / 'selfhost/components.zig'),
                   '-O' + mode, '-mcpu=' + cpu, '-femit-bin=' + str(output),
                   '--cache-dir', str(WORK / 'coordinator-cache' / label),
                   '--global-cache-dir', '/home/epentland/ai/canopy/.zig-global-cache']
        with (HERE / ('coordinator-build-' + name + '.log')).open('w') as log:
            done = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                  env={**os.environ, 'TMPDIR': str(WORK / 'tmp')})
        rows.append({'name': name, 'exit': done.returncode, 'command': command})
        (HERE / 'coordinator-builds.json').write_text(json.dumps(rows, indent=2) + '\n')
        print(name, done.returncode, flush=True)
