#!/usr/bin/env python3
"""Measure allocation scaling without modifying prior experiment reports.

Run capture/build-timing subcommands through scripts/build-slot.sh build.
Only the timing subcommand executes pinned timing runs; coordinate CPU 2 first.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time
from types import SimpleNamespace

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('closeout', HERE.parent / 'zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
# Historical helper has a shorter subprocess timeout; cache initialization can
# legitimately take several minutes with other compilers building on this host.
def call(argv, env, directory, label, expected=0):
    start = time.perf_counter_ns()
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, text=True, timeout=1200)
    (directory / (label + '.stderr')).write_text(result.stderr)
    (directory / (label + '.stdout')).write_text(result.stdout)
    record = {'argv': list(map(str, argv)), 'status': result.returncode,
              'elapsed_ns': time.perf_counter_ns() - start, 'stdout': result.stdout, 'stderr': result.stderr}
    q.common.save(directory / (label + '.json'), record)
    assert result.returncode == expected, record
    return record
q.call = call


def environment(zig, counted=True):
    env = dict(os.environ, ZIG=str(zig), MYLANG_ZIG=str(zig))
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE', 'MYL_CORE_LEAKCHECK'):
        env.pop(key, None)
    if counted:
        env['MYL_CORE_LEAKCHECK'] = '1'
    return env


def cases(phase):
    result = []
    for kind in ('array', 'object'):
        for size in (1, 16, 128):
            for action in ('control', 'hit', 'miss'):
                name = f'{kind}_{size}_{action}'
                answer = f'{kind} {4096 if action == "hit" else 32}\n'
                result.append((name, HERE / 'samples' / (name + '.my'), answer))
    result.append(('record', HERE / 'samples' / f'record_{phase}.my', '267560\n'))
    return result


def save_result(path, result):
    result['harness_sha256'] = q.common.digest(__file__)
    q.common.save(path, result)


def capture(a):
    env = environment(a.zig)
    result_path = HERE / (a.phase + '.json')
    result = json.loads(result_path.read_text()) if result_path.exists() else {'cases': {}, 'controls': {}}
    digest = q.common.digest(a.compiler)
    if 'compiler' in result:
        assert result['compiler']['sha256'] == digest, 'existing results belong to a different compiler'
    result['compiler'] = {'path': str(a.compiler), 'sha256': digest}
    result['allocation_note'] = 'Managed counters only; peak_live_bytes is not total process RSS.'
    for name, source, answer in cases(a.phase):
        if a.only and name not in a.only:
            continue
        lanes = result['cases'].setdefault(name, {})
        for mode, flags in q.common.MODES.items():
            if a.modes and mode not in a.modes:
                continue
            if mode != 'release' and name != 'record' and '_128_' not in name:
                continue
            if mode in lanes:
                assert lanes[mode]['source_sha256'] == q.common.digest(source), 'source changed after prior capture'
                continue
            lanes[mode] = q.lane(a, env, name, source, ['--experimental-zero-rc', *flags], mode, 0, answer)
            save_result(result_path, result)
            print('pass', a.phase, name, mode, flush=True)
    if not a.only or 'json_fixture' in a.only:
        anchors = result.setdefault('anchors', {})
        if 'json_fixture' not in anchors:
            anchors['json_fixture'] = q.lane(a, env, 'json_fixture', ROOT / 'src/stdlib/fixtures/json.my',
                                             ['--experimental-zero-rc', '--release'], 'release', 42)
            save_result(result_path, result)
            print('pass', a.phase, 'json_fixture', 'release', flush=True)
    if a.phase == 'after' and not a.only:
        for name, source, answer in cases(a.phase):
            # Representative RC controls for each operation and container type.
            if name not in ('array_128_hit', 'array_128_miss', 'object_128_hit', 'object_128_miss', 'record'):
                continue
            if name not in result['controls']:
                result['controls'][name] = q.lane(a, env, name, source, ['--release'], 'rc', 0, answer)
                save_result(result_path, result)
        name = 'record_explicit_copy'
        if name not in result['controls']:
            result['controls'][name] = q.lane(a, env, name, HERE / 'samples/record_before.my',
                                             ['--experimental-zero-rc', '--release'], 'release', 0, '267560\n')
            save_result(result_path, result)
    assert digest == q.common.digest(a.compiler)
    save_result(result_path, result)


def timing_cases(phase):
    return [('array', HERE / 'samples/array_timing.my', 'array 512000\n'),
            ('object', HERE / 'samples/object_timing.my', 'object 512000\n'),
            ('record', HERE / 'samples' / f'record_timing_{phase}.my', '5475560\n')]


def build_timing(a):
    env = environment(a.zig, False)
    result = {}
    for name, source, answer in timing_cases(a.phase):
        d = a.output / 'timing' / name
        d.mkdir(parents=True, exist_ok=True)
        built = q.call([a.compiler, 'build', source, '--experimental-zero-rc', '--release', '--zig', a.zig,
                        '--cache-dir', a.output / 'cache', '-o', d / 'program'], env, d, 'build')
        result[name] = {'source_sha256': q.common.digest(source), 'binary_sha256': q.common.digest(d / 'program'),
                        'compiler_sha256': q.common.digest(a.compiler), 'build_ns': built['elapsed_ns'], 'answer': answer}
        print('built timing', a.phase, name, flush=True)
    q.common.save(a.output / 'timing' / 'builds.json', result)


def timing(a):
    result = {'method': '2 warmup pairs then 9 alternating pairs, CPU 2, uninstrumented process wall time on shared host',
              'cases': {}}
    env = dict(os.environ)
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE', 'MYL_CORE_LEAKCHECK'):
        env.pop(key, None)
    records = {phase: json.loads((getattr(a, phase) / 'timing/builds.json').read_text()) for phase in ('before', 'after')}
    for name, _, answer in timing_cases('after'):
        observations = {'before': [], 'after': []}
        for repetition in range(11):
            for phase in (('before', 'after') if repetition % 2 == 0 else ('after', 'before')):
                binary = getattr(a, phase) / 'timing' / name / 'program'
                assert records[phase][name]['binary_sha256'] == q.common.digest(binary)
                start = time.perf_counter_ns()
                run = subprocess.run(['taskset', '-c', '2', str(binary)], env=env, capture_output=True, timeout=120)
                elapsed = time.perf_counter_ns() - start
                assert run.returncode == 0 and run.stdout.decode() == answer and not run.stderr, run
                if repetition >= 2:
                    observations[phase].append(elapsed)
        observations['median_ns'] = {phase: statistics.median(observations[phase]) for phase in ('before', 'after')}
        observations['speedup'] = observations['median_ns']['before'] / observations['median_ns']['after']
        observations['builds'] = {phase: records[phase][name] for phase in ('before', 'after')}
        result['cases'][name] = observations
        q.common.save(HERE / 'timing.json', result)
        print(name, observations['median_ns'], observations['speedup'], flush=True)


def memory(lane):
    m = lane['runs']['1']['memory']
    return {'allocs': m['allocs'], 'reallocs': m['reallocs'], 'allocated_bytes': m['alloc_bytes'] + m['realloc_added_bytes'],
            'peak_live_bytes': m['peak_live_bytes'], 'live_bytes_at_exit': m['live_bytes_at_exit']}


def summarize(_):
    phases = {phase: json.loads((HERE / (phase + '.json')).read_text()) for phase in ('before', 'after')}
    result = {'whole_program': {}, 'lookup_delta': {},
              'lookup_delta_note': 'Hit/miss minus matched construction-only control, divided by 32 lookups; peak is not subtracted.'}
    for name, _, _ in cases('after'):
        row = {phase: memory(phases[phase]['cases'][name]['release']) for phase in ('before', 'after')}
        result['whole_program'][name] = row
        if name == 'record' or name.endswith('_control'):
            continue
        control = name.rsplit('_', 1)[0] + '_control'
        delta = {}
        for phase in ('before', 'after'):
            base = memory(phases[phase]['cases'][control]['release'])
            delta[phase] = {metric: (row[phase][metric] - base[metric]) / 32
                            for metric in ('allocs', 'reallocs', 'allocated_bytes')}
        result['lookup_delta'][name] = delta
    # Copying is still explicit: the optimized compiler must preserve this work.
    copied = memory(phases['after']['controls']['record_explicit_copy'])
    assert copied['allocs'] == result['whole_program']['record']['before']['allocs'], (copied, result['whole_program']['record'])
    result['explicit_record_copy_control'] = copied
    result['whole_program']['json_fixture'] = {phase: memory(phases[phase]['anchors']['json_fixture']) for phase in ('before', 'after')}
    for kind in ('array', 'object'):
        hits = [result['lookup_delta'][f'{kind}_{size}_hit']['after'] for size in (1, 16, 128)]
        assert all(value == hits[0] for value in hits), (kind, hits)
        for size in (1, 16, 128):
            miss = result['lookup_delta'][f'{kind}_{size}_miss']['after']
            assert all(value == 0 for value in miss.values()), (kind, size, miss)
    q.common.save(HERE / 'summary.json', result)
    print(json.dumps(result, indent=2), flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    for name, handler in (('capture', capture), ('build-timing', build_timing)):
        s = sub.add_parser(name)
        s.set_defaults(handler=handler)
        for key in ('compiler', 'zig', 'output'):
            s.add_argument('--' + key, type=Path, required=True)
        s.add_argument('--phase', choices=('before', 'after'), required=True)
        if name == 'capture':
            s.add_argument('--only', nargs='+')
            s.add_argument('--modes', nargs='+', choices=q.common.MODES)
    s = sub.add_parser('timing')
    s.set_defaults(handler=timing)
    for phase in ('before', 'after'):
        s.add_argument('--' + phase, type=Path, required=True)
    s = sub.add_parser('summarize')
    s.set_defaults(handler=summarize)
    a = p.parse_args()
    for key, value in vars(a).items():
        if isinstance(value, Path):
            setattr(a, key, value.resolve())
    if hasattr(a, 'output'):
        a.output.mkdir(parents=True, exist_ok=True)
    a.handler(a)


if __name__ == '__main__':
    main()
