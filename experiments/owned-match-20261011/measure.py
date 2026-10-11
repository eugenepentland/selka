#!/usr/bin/env python3
"""Compare fresh-match transfers with the frozen owned-try compiler."""
import argparse, importlib.util, json, os, statistics, subprocess, sys, time
from pathlib import Path
from types import SimpleNamespace
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('closeout', HERE.parent/'zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)


def cases(phase):
    return [
        ('json', ROOT/'src/stdlib/fixtures/json.my', 42, None),
        ('strings', ROOT/'src/stdlib/fixtures/strings.my', 42, None),
        ('json_nested', HERE.parent/'owned-payload-20261011/samples/json_nested.my', 0, '121000\n'),
        ('json_text', HERE/'samples/json_text.my', 0, '8289000\n'),
        ('boxed', HERE/'samples'/('boxed_'+phase+'.my'), 0, '10324\n'),
    ]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('before', 'after', 'zig', 'output'):
        p.add_argument('--'+key, type=Path, required=True)
    args = p.parse_args()
    for key in ('before', 'after', 'zig', 'output'):
        setattr(args, key, getattr(args, key).resolve())
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)
    timing_env = dict(env)
    timing_env.pop('MYL_CORE_LEAKCHECK')
    result = {'harness_sha256': q.common.digest(__file__), 'compilers': {}, 'cases': {}, 'controls': {}}
    for phase in ('before', 'after'):
        compiler = getattr(args, phase)
        result['compilers'][phase] = {'path': str(compiler), 'sha256': q.common.digest(compiler)}
        a = SimpleNamespace(compiler=compiler, zig=args.zig, output=args.output/phase)
        for name, source, status, answer in cases(phase):
            lanes = {}
            for mode, flags in q.common.MODES.items():
                lanes[mode] = q.lane(a, env, name, source, ['--experimental-zero-rc', *flags], mode, status, answer)
                print('pass', phase, name, mode, flush=True)
            result['cases'].setdefault(name, {})[phase] = lanes
            q.common.save(HERE/'results.json', result)
            if name not in ('json', 'strings'):
                d = a.output/'timing'/name
                d.mkdir(parents=True, exist_ok=True)
                q.call([compiler, 'build', source, '--experimental-zero-rc', '--release', '--zig', args.zig,
                        '--cache-dir', a.output/'cache', '-o', d/'program'], timing_env, d, 'build')
        if phase == 'after':
            for name, source, status, answer in cases(phase):
                result['controls'][name] = q.lane(a, env, name, source, ['--release'], 'rc', status, answer)
            # Keeping the explicit copy must preserve the baseline allocation count.
            result['controls']['boxed_explicit_copy'] = q.lane(a, env, 'boxed_explicit_copy', HERE/'samples/boxed_before.my',
                ['--experimental-zero-rc', '--release'], 'release', 0, '10324\n')
    result['timing'] = {}
    for name, _, _, answer in cases('after'):
        if name in ('json', 'strings'):
            continue
        timing = {'method': '2 warmup pairs then 9 alternating pairs, CPU 2, uninstrumented; shared host', 'before': [], 'after': []}
        for repetition in range(11):
            for phase in (('before', 'after') if repetition % 2 == 0 else ('after', 'before')):
                start = time.perf_counter_ns()
                run = subprocess.run(['taskset', '-c', '2', str(args.output/phase/'timing'/name/'program')],
                                     env=timing_env, capture_output=True, timeout=120)
                elapsed = time.perf_counter_ns()-start
                assert run.returncode == 0 and run.stdout.decode() == answer and not run.stderr, run
                if repetition >= 2:
                    timing[phase].append(elapsed)
        timing['median_ns'] = {phase: statistics.median(timing[phase]) for phase in ('before', 'after')}
        timing['speedup'] = timing['median_ns']['before']/timing['median_ns']['after']
        result['timing'][name] = timing
    result['summary'] = {}
    for name, phases in result['cases'].items():
        row = {}
        for phase, lanes in phases.items():
            memory = lanes['release']['runs']['1']['memory']
            row[phase] = {key: memory[key] for key in ('allocs', 'reallocs', 'peak_live_bytes', 'live_bytes_at_exit')}
            row[phase]['allocated_bytes'] = memory['alloc_bytes']+memory['realloc_added_bytes']
        for metric in ('allocs', 'allocated_bytes', 'peak_live_bytes'):
            row[metric+'_reduction_percent'] = 100*(1-row['after'][metric]/row['before'][metric])
        result['summary'][name] = row
    for record in result['compilers'].values():
        assert record['sha256'] == q.common.digest(record['path'])
    baseline = result['cases']['boxed']['before']['release']['runs']['1']['memory']
    explicit = result['controls']['boxed_explicit_copy']['runs']['1']['memory']
    assert baseline['allocs'] == explicit['allocs'], (baseline, explicit)
    q.common.save(HERE/'results.json', result)
    print(json.dumps({'summary': result['summary'], 'timing': result['timing']}, indent=2), flush=True)

if __name__ == '__main__':
    main()
