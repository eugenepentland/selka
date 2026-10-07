#!/usr/bin/env python3
"""Fresh native-cache controls on the retained immutable Core RED fixture."""
from pathlib import Path

source = Path(__file__).with_name('reproduce.py').read_text()
exec(compile(source.split('\nenvironment = os.environ.copy()')[0],
             str(Path(__file__).with_name('reproduce.py')), 'exec'))

assert (WORK / 'value.h').read_text() == '#define VALUE 8\n'
environment = os.environ.copy()
environment['ZIG'] = str(Path('/home/epentland/.local/bin/zig').resolve())
environment['ZIG_GLOBAL_CACHE_DIR'] = str(WORK / 'zig-global')
argv = json.loads((EVIDENCE / 'invocation.json').read_text())['argv']
local = WORK / 'core-cache/zig-local'
local.rename(WORK / 'zig-local-before-controls')
first = phase('control-local-only', 8, environment, argv)
local.rename(WORK / 'zig-local-after-local-control')
(WORK / 'zig-global').rename(WORK / 'zig-global-before-both-control')
second = phase('control-both-fresh', 8, environment, argv)
save(EVIDENCE / 'controls-summary.json', {
    'local_only': first, 'both_fresh': second,
    'original_red_preserved': True,
    'status': 'GREEN' if first['correct'] and second['correct'] else 'RED'})
