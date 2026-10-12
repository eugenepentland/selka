#!/usr/bin/env python3
"""Count and audit independent repetition; this harness owns bounded build leases."""
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
parser.add_argument('--zig', type=Path, required=True)
parser.add_argument('--phase', required=True)
parser.add_argument('--source-commit', required=True, help='exact source revision of the supplied compiler')
parser.add_argument('--lists-only', action='store_true')
args = parser.parse_args()
args.compiler = args.compiler.resolve()
args.zig = args.zig.resolve()
args.output = ROOT / '.tmp/memory-closeout/A04/repetition' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'use a new evidence phase'
evidence.mkdir()
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
spec = importlib.util.spec_from_file_location('repeat_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(name, None)
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler),
          'source_commit': args.source_commit,
          'fixture_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'harness_sha256': digest(Path(__file__)), 'cases': {}, 'negative_cases': {},
          'scope': 'lists only; text/byte helper contracts pending' if args.lists_only else 'full repetition contract',
          'limitations': 'Managed counters are not RSS. Build times include no admitted queue wait but are not controlled performance samples.'}
failures = 0
sources = [('lists', HERE / 'lists.my')]
if not args.lists_only:
    sources.append(('complete', ROOT / 'tests/lang/a04_repetition_ownership.my'))
for name, source in sources:
    report['cases'][name] = {}
    with admission('build'):
        for mode, flags in q.common.MODES.items():
            try:
                row = dict(q.lane(args, env, name, source, ['--experimental-zero-rc', *flags], mode, 0, answer=''), status='passed')
            except (AssertionError, subprocess.SubprocessError, OSError) as error:
                row = dict(status='failed', error=str(error), source_sha256=digest(source))
                failures += 1
            report['cases'][name][mode] = row
            raw = args.output / name / mode
            target = evidence / 'raw' / name / mode
            target.mkdir(parents=True, exist_ok=True)
            for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
                for artifact in raw.glob(pattern):
                    shutil.copyfile(artifact, target / artifact.name)
            (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(name, mode, row['status'], flush=True)
if not args.lists_only:
    with admission('build'):
        for name, command, diagnostic in [('unsupported_place', 'check', 'E_TYPE'), ('overflow_signed', 'run', 'R_MEMORY_BUDGET'), ('overflow_unsigned', 'run', 'R_MEMORY_BUDGET')]:
            source = HERE / (name + '.my')
            cmd = [str(args.compiler), command, str(source), '--experimental-zero-rc']
            if command == 'run':
                cmd += ['--release', '--max-memory', '8M']
            ran = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
            good = ran.returncode == 1 and diagnostic in ran.stderr
            failures += not good
            report['negative_cases'][name] = dict(command=cmd, status='passed' if good else 'failed', exit_code=ran.returncode, expected=diagnostic, stdout=ran.stdout, stderr=ran.stderr, source_sha256=digest(source))
assert digest(args.compiler) == report['compiler_sha256'], 'compiler changed'
report['summary'] = {'failed': failures, 'lanes': sum(len(rows) for rows in report['cases'].values()), 'negative_cases': len(report['negative_cases'])}
(evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
print(report['summary'])
raise SystemExit(bool(failures))
