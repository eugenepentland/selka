#!/usr/bin/env python3
"""Actual LLVM ELF accounted/unaccounted boundary executions, with full traps."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts

REVISION = '27de73d302d23a9efaf811d541f1cb723323c434'
MAXIMUM = (1 << 63) - 1
MINIMUM = -(1 << 63)
CASES = (
    {'name': 'admitted_positive', 'count': 32, 'seed': 17, 'offset': 0},
    {'name': 'zero_endpoint', 'count': 32, 'seed': 0, 'offset': 0},
    {'name': 'negative_endpoint', 'count': 32, 'seed': -1, 'offset': 0},
    {'name': 'short_negative', 'count': 3, 'seed': -1, 'offset': 0},
    {'name': 'zero_trip_overflowing_endpoint', 'count': 0, 'seed': MAXIMUM, 'offset': 1},
    {'name': 'first_overflow_after_output', 'count': 32, 'seed': MAXIMUM, 'offset': 1, 'trap': 'R_OVERFLOW'},
    {'name': 'negative_overflow_after_output', 'count': 32, 'seed': MINIMUM, 'offset': -1, 'trap': 'R_OVERFLOW'},
    {'name': 'later_body_overflow_after_output', 'count': 32, 'seed': 0, 'offset': MAXIMUM, 'trap': 'R_OVERFLOW'},
    {'name': 'first_heap_budget_refusal', 'count': 400000, 'seed': 17, 'offset': 0,
     'memory_limit': 1 << 20, 'trap': 'R_MEMORY_BUDGET'},
)


def stamp():
    return datetime.now(timezone.utc).isoformat()


def expected(case):
    if case['count'] <= 0:
        return 0
    first = case['seed'] + case['offset']
    return case['count'] + first % 1009 + (first + (case['count'] - 1) * 13) % 1009


def outcome(binary, case, cpu):
    environment = {**runner.runtime_environment(), 'MYLANG_OPTIONS': '--print-result',
                   'MYLANG_MEMORY_LIMIT': str(case.get('memory_limit', 128 << 20))}
    argv = ['taskset', '-c', str(cpu), str(binary), str(case['count']), str(case['seed']), str(case['offset'])]
    process = subprocess.run(argv, env=environment, capture_output=True, text=True, timeout=60)
    assert process.returncode >= 0, 'unexpected signal'
    raw_stdout, raw_stderr = process.stdout, process.stderr
    trap = {'code': '', 'path': '', 'line': 0, 'column': 0, 'frames': [], 'detail': None}
    for line in raw_stderr.split('\n'):
        location = re.fullmatch(r'(.*):(\d+):(\d+): error\[([^]]+)\]:.*', line)
        if location:
            trap.update(code=location[4], path=location[1], line=int(location[2]), column=int(location[3]))
        frame = re.fullmatch(r'  in (.*) at (.*):(\d+):(\d+)', line)
        if frame:
            trap['frames'].append({'function': frame[1], 'path': frame[2], 'line': int(frame[3]), 'column': int(frame[4])})
        if line.startswith('\x1eMYLANG-TRAP '):
            assert trap['detail'] is None
            trap['detail'] = json.loads(line[len('\x1eMYLANG-TRAP '):])
    failed = bool(raw_stderr)
    value = 0; stdout = raw_stdout
    if not failed:
        assert raw_stdout.endswith('\n')
        prefix, separator, result = raw_stdout[:-1].rpartition('\n')
        assert separator
        value = int(result)
        stdout = prefix + '\n'
        assert value == expected(case) and process.returncode == value % 256
    assert stdout == '17\n', (case, process.returncode, raw_stdout, raw_stderr)
    assert trap['code'] == case.get('trap', '')
    assert failed == ('trap' in case)
    if failed:
        assert process.returncode == 1 and trap['frames']
    return {'argv': argv, 'environment_overrides': {key: environment[key] for key in ('MYLANG_OPTIONS', 'MYLANG_MEMORY_LIMIT')},
            'run': {'value': value, 'stdout': stdout, 'stderr': raw_stderr, 'status': process.returncode, 'failed': failed,
                    'raw_stdout': raw_stdout, 'trap': trap}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=4)
    args = parser.parse_args()
    path = args.manifest.resolve(); digest = runner.digest(path); manifest = json.loads(path.read_text())
    holdouts.check_manifest(path, digest, manifest)
    identity = manifest['identity']
    assert identity['source_revision'] == REVISION
    assert identity['compiler_build_receipt']['receipt']['compiler_optimize'] == 'ReleaseFast'
    source = Path(__file__).with_name('remainder_semantics.my')
    bindings = {str(item): runner.digest(item) for item in (source, Path(__file__), ROOT / 'benchmarks/runtime/runner.py',
                ROOT / 'benchmarks/runtime/diagnostics/holdouts.py')}
    work = args.work.resolve(); work.mkdir()
    report = {'schema': 'mylang-goal110-nonnegative-rem-actual-llvm-semantics-v1', 'status': 'in_progress',
              'source_revision': REVISION, 'source': str(source), 'source_and_helper_sha256': bindings,
              'manifest': str(path), 'manifest_sha256': digest, 'manifest_identity': identity,
              'started_utc': stamp(), 'cpu': args.cpu, 'builds': {}, 'outcomes': [],
              'purpose': 'Untimed correctness on actual LLVM backend ELFs; distinct from QBE-executed LLVM scalar policy units.'}
    for policy in ('accounted', 'unaccounted'):
        directory = work / policy; directory.mkdir()
        command = list(identity['commands']['collections/my-llvm'])
        command[2] = str(source)
        binary = directory / 'remainder-semantics'
        command[command.index('-o') + 1] = str(binary)
        command[command.index('--cache-dir') + 1] = str(directory / 'mycache')
        if policy == 'accounted':
            command.append('--step-accounting')
        actual = [identity['build_wrapper'], 'build', *command]
        environment = {key: str(directory / key.lower()) for key in ('TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')}
        for item in environment.values():
            Path(item).mkdir()
        print('Building actual LLVM ' + policy, flush=True)
        process = subprocess.run(actual, cwd=ROOT, env={**runner.runtime_environment(), **environment},
                                 capture_output=True, text=True, timeout=1800)
        assert process.returncode == 0, process.stdout + process.stderr
        backend_path = Path(str(binary) + '.qbe-manifest.json'); backend = json.loads(backend_path.read_text())
        assert backend['backend'] == 'llvm' and str(backend['optimization']) == '3' and backend['lto']
        report['builds'][policy] = {'command': actual, 'environment': environment, 'exit_status': process.returncode,
                                    'stdout': process.stdout, 'stderr': process.stderr, 'binary': str(binary),
                                    'binary_sha256': runner.digest(binary), 'backend_manifest': str(backend_path),
                                    'backend_manifest_sha256': runner.digest(backend_path)}
    for case in CASES:
        results = {policy: outcome(Path(build['binary']), case, args.cpu) for policy, build in report['builds'].items()}
        # Preserve complete raw streams, all frames and structured detail in the equality.
        assert results['accounted']['run'] == results['unaccounted']['run'], (case, results)
        report['outcomes'].append({'input': case, **results})
        print('PASS actual LLVM ' + case['name'], flush=True)
    positive = report['outcomes'][0]['unaccounted']['run']
    assert positive['value'] == 469 and positive['status'] == 213
    assert bindings == {item: runner.digest(item) for item in bindings}
    holdouts.check_manifest(path, digest, manifest)
    for build in report['builds'].values():
        assert build['binary_sha256'] == runner.digest(build['binary'])
        assert build['backend_manifest_sha256'] == runner.digest(build['backend_manifest'])
    report.update(status='complete', finished_utc=stamp())
    with args.output.open('x') as target:
        target.write(json.dumps(report, indent=2) + '\n')
    print('PASS18 actual LLVM executions/9 exact accounted-unaccounted boundary pairs; no timing recorded')


if __name__ == '__main__':
    main()
