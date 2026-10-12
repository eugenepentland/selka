#!/usr/bin/env python3
"""Qualify copied slices and retained readonly fusion; owns bounded admission."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--phase', required=True)
parser.add_argument('--source-commit', required=True)
parser.add_argument('--prototype-diff', action='store_true')
args = parser.parse_args()
args.compiler = args.compiler.resolve()
args.zig = Path(os.environ['ZIG'])
args.output = ROOT / '.tmp/memory-closeout/A04/slices' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'choose a fresh phase'
evidence.mkdir()
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
spec = importlib.util.spec_from_file_location('slice_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
oracles = json.loads((HERE / 'oracles.json').read_text())
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler), 'source_commit': args.source_commit,
          'prototype_diff': subprocess.check_output(['git', 'diff', '--', 'src'], cwd=ROOT, text=True) if args.prototype_diff else '',
          'harness_sha256': digest(Path(__file__)), 'cases': {},
          'limitations': 'Correctness, managed counters and structural audits; no timing/RSS or allocation-saving claim.'}
env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(name, None)
sources = [('regressions', ROOT / 'tests/lang/a04_slice_snapshots.my', ''),
           ('s1_reads', ROOT / 'test/core/s1_reads.my', oracles['s1_reads']['stdout']),
           ('s1_views', ROOT / 'test/core/s1_views.my', oracles['s1_views']['stdout'])]
for name, source, answer in sources:
    lanes = [(mode, ['--experimental-zero-rc', *flags]) for mode, flags in q.common.MODES.items()]
    if name != 'regressions':
        lanes.append(('ordinary', ['--release']))
    with admission('build'):
        for mode, flags in lanes:
            try:
                row = dict(q.lane(args, env, name, source, flags, mode, 0, answer=answer), status='passed')
            except Exception as error:
                row = {'status': 'failed', 'error': str(error), 'source_sha256': digest(source)}
            report['cases'][name + '/' + mode] = row
            target = evidence / 'raw' / name / mode
            target.mkdir(parents=True, exist_ok=True)
            for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
                for artifact in (args.output / name / mode).glob(pattern):
                    shutil.copyfile(artifact, target / artifact.name)
            (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(name, mode, row['status'], flush=True)
assert digest(args.compiler) == report['compiler_sha256']
report['summary'] = {'lanes': len(report['cases']), 'failed': sum(row['status'] != 'passed' for row in report['cases'].values())}
(evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(bool(report['summary']['failed']))
