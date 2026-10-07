#!/usr/bin/env python3
"""Confine Clang resource lookup to the already inventoried adjacent library."""
import json
import probe

library = probe.TOOL.parent / 'lib'
empty = probe.WORK / 'empty-sysroot'
row = probe.run('resource-confined', ['--no-default-config', '-nostdinc', '-nostdinc++',
                  '--gcc-toolchain=' + str(empty), '--sysroot=' + str(empty),
                  '-resource-dir=' + str(library)])
(probe.EVIDENCE / 'resource-control.json').write_text(json.dumps(row, indent=2) + '\n')
