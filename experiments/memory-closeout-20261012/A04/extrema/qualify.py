#!/usr/bin/env python3
"""Qualify list extrema ownership, old scalar behavior and located empty traps."""
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
sys.path.insert(0, str(HERE.parent))
from build_admission import admission
import ownership_commands as ownership

parser = argparse.ArgumentParser(description=__doc__)
ownership.add_option(parser)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--source-commit', required=True)
parser.add_argument('--phase', required=True)
parser.add_argument('--prototype-diff', action='store_true')
parser.add_argument('--baseline', type=Path)
args = parser.parse_args()
args.compiler = args.compiler.resolve()
args.zig = Path(os.environ['ZIG'])
args.output = ROOT / '.tmp/memory-closeout/A04/extrema' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'choose a fresh phase'
evidence.mkdir()
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
spec = importlib.util.spec_from_file_location('extrema_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler), 'source_commit': args.source_commit,
          'prototype_diff': subprocess.check_output(['git', 'diff', '--', 'src', 'SPEC.md'], cwd=ROOT, text=True) if args.prototype_diff else '',
          'default_ownership': args.default_ownership, 'ownership_support_sha256': ownership.digest(),
          'harness_sha256': digest(Path(__file__)), 'cases': {}, 'negatives': {},
          'limitations': 'Semantic/counter/structural qualification; no exclusive runtime, compile scaling or RSS claim.'}
env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(name, None)


def save():
    (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


def snapshot(name, mode):
    target = evidence / 'raw' / name / mode
    target.mkdir(parents=True, exist_ok=True)
    for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
        for artifact in (args.output / name / mode).glob(pattern):
            shutil.copyfile(artifact, target / artifact.name)


def trap(source, name, mode, flags):
    d = args.output / name / mode
    d.mkdir(parents=True, exist_ok=True)
    source_copy = d / 'main.my'
    source_copy.write_bytes(source.read_bytes())
    binary, llvm = d / 'program', d / 'program.ll'
    q.call([args.compiler, 'build', source_copy, '--zig', args.zig, '--cache-dir', args.output / 'cache',
            *flags, '--counters', '--emit-llvm', llvm, '-o', binary], env, d, 'build')
    checked = args.default_ownership or '--experimental-zero-rc' in flags
    if checked:
        q.prior.clean_ir(llvm)
        symbols = subprocess.check_output(['nm', str(binary)], text=True)
        assert not any(s in symbols for s in ('myl_core_retain', 'myl_core_release', 'myl_core_share'))
    counts = d / 'counts.json'
    result = q.call([binary], dict(env, MYLANG_COUNTERS=str(counts)), d, 'run', expected=1)
    assert 'R_LIST_BOUNDS' in result['stderr'] and 'main.my:3:' in result['stderr'], result
    assert result['stdout'] == '', result
    audit = q.common.audit.audit(counts)
    if checked:
        assert audit['observed_rc_free'], audit
    return {'status': 'passed', 'source_sha256': digest(source), 'binary_sha256': digest(binary),
            'llvm_sha256': digest(llvm), 'run': result, 'audit': audit}


cases = [('complete', ROOT / 'tests/lang/a04_list_extrema.my', False), ('view_copy', HERE / 'view_copy.my', False),
         ('empty_min', HERE / 'empty_min.my', True), ('empty_max', HERE / 'empty_max.my', True)]
for name, source, is_trap in cases:
    lanes = [(mode, [*ownership.flags(args), *flags]) for mode, flags in q.common.MODES.items()]
    if not args.default_ownership and name != 'view_copy':
        lanes.append(('ordinary', ['--release']))
    with admission('build'):
        for mode, flags in lanes:
            try:
                row = trap(source, name, mode, flags) if is_trap else dict(ownership.lane(q, args, env, name, source, flags, mode, 0, answer=''), status='passed')
            except (AssertionError, OSError, subprocess.SubprocessError) as error:
                row = {'status': 'failed', 'error': str(error), 'source_sha256': digest(source)}
            report['cases'][name + '/' + mode] = row
            snapshot(name, mode)
            save()
            print(name, mode, row['status'], flush=True)
with admission('build'):
    for name, expected in [('view_replaced', 'E_ZERO_RC_VIEW_INVALIDATED'), ('view_moved', 'E_ZERO_RC_VIEW_INVALIDATED'),
                           ('borrow_escape', 'E_SINGLE_OWNER_BORROW')]:
        source = HERE / (name + '.my')
        command = [str(args.compiler), 'check', str(source), *ownership.flags(args)]
        run = subprocess.run(command, capture_output=True, text=True, cwd=ROOT, env=env, timeout=60)
        passed = run.returncode == 1 and expected in run.stderr
        report['negatives'][name] = {'status': 'passed' if passed else 'failed', 'source_sha256': digest(source),
                                     'command': command, 'exit_status': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr, 'expected': expected}
        print(name, report['negatives'][name]['status'], flush=True)
        save()
if args.baseline:
    assert not args.default_ownership
    source = ROOT / 'tests/lang/a04_list_extrema.my'
    command = [str(args.baseline), 'check', str(source), '--experimental-zero-rc']
    with admission('build'):
        run = subprocess.run(command, capture_output=True, text=True, cwd=ROOT, env=env, timeout=60)
    report['baseline'] = {'compiler': str(args.baseline), 'compiler_sha256': digest(args.baseline), 'command': command,
                          'source_sha256': digest(source), 'status': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr}
assert digest(args.compiler) == report['compiler_sha256'], 'compiler changed'
report['summary'] = {'native_lanes': len(report['cases']), 'negative_cases': len(report['negatives']),
                     'failed': sum(row['status'] != 'passed' for group in ('cases', 'negatives') for row in report[group].values())}
save()
print(report['summary'], flush=True)
raise SystemExit(bool(report['summary']['failed']))
