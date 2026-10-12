#!/usr/bin/env python3
"""Run all A04 follow-ups against the immutable common Support7 installation.

Individual qualification adapters own shared admission; this orchestrator never
holds a lease around them. The source survey alone gets an explicit build lease.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
A04 = HERE.parent
ROOT = HERE.parents[3]
COMPILER = ROOT.parent / 'mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang'
SHA = '540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef'
SOURCE = 'bed11cf3bf3102ffec44487e431a1573fdf02ad5'
PHASE = 'support7-01'
LOGS = ROOT / '.tmp/memory-closeout/A04/common-support7'
LOGS.mkdir(parents=True, exist_ok=True)
assert hashlib.sha256(COMPILER.read_bytes()).hexdigest() == SHA
commands = {}
for name in ('selections', 'formatting', 'repetition', 'rendering', 'slices', 'extrema', 'tuples', 'additional-migrations'):
    command = [sys.executable, '-B', str(A04 / name / 'qualify.py'), '--compiler', str(COMPILER), '--source-commit', SOURCE, '--phase', PHASE]
    if name in ('formatting', 'repetition', 'rendering', 'additional-migrations'):
        command += ['--zig', os.environ['ZIG']]
    commands[name] = command
commands['migration-survey'] = [str(ROOT / 'scripts/build-slot.sh'), 'build', sys.executable, '-B', str(A04 / 'migrations/check.py'), '--compiler', str(COMPILER), '--phase', 'check-support7']
commands['migration-tests'] = [sys.executable, '-B', str(A04 / 'migrations/run_tests.py'), '--compiler', str(COMPILER), '--survey', str(A04 / 'migrations/check-support7.json'), '--phase', 'execution-support7', '--modes', 'release', 'debug', 'verify', 'optimized_debug', 'no_facts']
selected = sys.argv[1:] or list(commands)
assert all(name in commands for name in selected)
report_path = HERE / 'followups.json'
report = json.loads(report_path.read_text()) if report_path.exists() else {'compiler_sha256': SHA, 'source_commit': SOURCE, 'steps': {}}
assert all(name not in report['steps'] for name in selected), 'completed attempts are immutable'
for name in selected:
    command = commands[name]
    log = LOGS / (name + '.log')
    assert not log.exists(), 'choose a separate new phase for retries'
    print(name, 'started', flush=True)
    with log.open('w') as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    report['steps'][name] = {'command': command, 'exit_status': result.returncode, 'log': str(log.relative_to(ROOT))}
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(name, 'finished', result.returncode, flush=True)
    assert hashlib.sha256(COMPILER.read_bytes()).hexdigest() == SHA
raise SystemExit(any(row['exit_status'] for row in report['steps'].values()))
