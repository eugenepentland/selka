#!/usr/bin/env python3
"""Count borrowed rendering across emission modes and replay identical artifacts."""
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
sys.path.insert(0, str(ROOT / "experiments/memory-closeout-20261012/A04"))
import ownership_commands as ownership
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

parser = argparse.ArgumentParser(description=__doc__)
ownership.add_option(parser)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--zig', type=Path, required=True)
parser.add_argument('--phase', required=True)
parser.add_argument('--source-commit', required=True)
parser.add_argument('--prototype-diff', action='store_true')
parser.add_argument('--baseline', type=Path)
args = parser.parse_args()
args.compiler = args.compiler.resolve()
args.zig = args.zig.resolve()
args.output = ROOT / '.tmp/memory-closeout/A04/rendering' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'use a new evidence phase'
evidence.mkdir()
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
spec = importlib.util.spec_from_file_location('render_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(name, None)
source = ROOT / 'tests/lang/a04_render_borrows.my'
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler), 'source_commit': args.source_commit,
          'prototype_diff': subprocess.check_output(['git', 'diff', '--', 'src'], cwd=ROOT, text=True) if args.prototype_diff else '',
          'fixture_sha256': digest(source), 'default_ownership': args.default_ownership, 'ownership_support_sha256': ownership.digest(), 'harness_sha256': digest(Path(__file__)), 'lanes': {}, 'replay': {},
          'limitations': 'Managed counters omit native rendering buffer reallocations and are not RSS or exclusive runtime samples.'}
failures = 0


def save():
    (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


def lane(name, flags, mode):
    global failures
    try:
        row = dict(ownership.lane(q, args, env, name, source, flags, mode, 0, answer=''), status='passed')
    except (AssertionError, subprocess.SubprocessError, OSError) as error:
        row = dict(status='failed', error=str(error))
        failures += 1
    raw = args.output / name / mode
    target = evidence / 'raw' / name / mode
    target.mkdir(parents=True, exist_ok=True)
    for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
        for artifact in raw.glob(pattern):
            shutil.copyfile(artifact, target / artifact.name)
    report['lanes'][name + '/' + mode] = row
    save()
    print(name, mode, row['status'], flush=True)


with admission('build'):
    for mode, flags in q.common.MODES.items():
        lane('zero', [*ownership.flags(args), *flags], mode)
with admission('build'):
    if not args.default_ownership:
        lane('ordinary', ['--release'], 'release')
    for mode, flags in [('release', ['--release']), ('debug', ['--unoptimized'])]:
        raw = args.output / 'zero' / mode
        replay = []
        for attempt in range(2):
            cmd = [str(args.compiler), 'build', str(raw / 'main.my'), '--zig', str(args.zig), '--cache-dir', str(args.output / 'cache'),
                   *ownership.flags(args), *flags, '--counters', '-o', str(raw / 'program'), '--report']
            ran = subprocess.run(cmd, env=env, cwd=ROOT, capture_output=True, text=True, timeout=120)
            lines = [json.loads(line) for line in ran.stderr.splitlines() if line.startswith('{')]
            row = {'command': cmd, 'status': ran.returncode, 'stdout': ran.stdout, 'stderr': ran.stderr,
                   'reports': lines, 'binary_sha256': digest(raw / 'program') if (raw / 'program').exists() else None}
            replay.append(row)
        good = all(row['status'] == 0 for row in replay) and bool(replay[-1]['reports']) and replay[-1]['reports'][-1]['program'] == 'replayed'
        if good:
            ran = subprocess.run([str(raw / 'program')], cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
            good = ran.returncode == 0 and ran.stdout == '' and ran.stderr == ''
        failures += not good
        report['replay'][mode] = {'status': 'passed' if good else 'failed', 'builds': replay}
        save()
if args.baseline:
    assert not args.default_ownership, 'historical controls require a separate opt-in qualification phase'
    candidate = args.compiler
    args.compiler = args.baseline.resolve()
    report['baseline'] = {'compiler': str(args.compiler), 'sha256': digest(args.compiler), 'source_commit': 'fbfcaa7a923186a8e773c3760f81c10aa345a432'}
    with admission('build'):
        lane('C0-ordinary', ['--release'], 'release')
    args.compiler = candidate
assert digest(args.compiler) == report['compiler_sha256'], 'compiler changed'
report['summary'] = {'failed': failures, 'lanes': len(report['lanes']), 'replay_modes': len(report['replay'])}
save()
raise SystemExit(bool(failures))
