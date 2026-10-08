#!/usr/bin/env python3
"""Continue after retained fixture-directory name collision in command-02."""
import json
import probe

empty = probe.WORK / 'empty-sysroot'
rows = [probe.run('sysroot-only', ['--sysroot=' + str(empty)]),
        probe.run('confined-search', ['--no-default-config', '-nostdinc', '-nostdinc++',
                  '--gcc-toolchain=' + str(empty), '--sysroot=' + str(empty)])]
(probe.EVIDENCE / 'search-controls.json').write_text(json.dumps(rows, indent=2) + '\n')
