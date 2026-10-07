#!/usr/bin/env python3
"""LLVM-only generic search flags, with no production policy change."""
import json
import probe

empty = probe.WORK / 'empty-sysroot'
empty.mkdir(parents=True)
rows = [probe.run('empty-gcc', ['--gcc-toolchain=' + str(empty)]),
        probe.run('empty-sysroot', ['--sysroot=' + str(empty)]),
        probe.run('confined-search', ['--no-default-config', '-nostdinc', '-nostdinc++',
                  '--gcc-toolchain=' + str(empty), '--sysroot=' + str(empty)])]
(probe.EVIDENCE / 'search-controls.json').write_text(json.dumps(rows, indent=2) + '\n')
