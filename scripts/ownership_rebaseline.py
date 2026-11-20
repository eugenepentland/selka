#!/usr/bin/env python3
"""Observe ownership benchmark baselines under caller-owned ordinary admission.

No timing admission, load window or favorable rerun is performed. Raw samples
remain in the requested private work directory. Runtime fixture sizes and
iteration counts come from the existing 40-case baseline.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def module_at(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def command(arguments, *, cwd=ROOT, timeout=1800):
    result = subprocess.run([str(value) for value in arguments], cwd=cwd,
                            capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {arguments}\n"
                           f"{result.stdout.decode(errors='replace')}"
                           f"{result.stderr.decode(errors='replace')}")
    return result.stdout, result.stderr


def save(work, report):
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


def parity(args, work):
    harness = module_at('ownership_parity', ROOT / 'bench/parity/bench_parity.py')
    benches = harness.discover([])
    tools = {'selka': str(args.compiler), 'zig': str(args.zig), 'rustc': None}
    report = {'suite': 'parity', 'rounds': args.rounds, 'mode': args.mode,
              'load_build': os.getloadavg(), 'benchmarks': {}}
    jobs = {}
    for bench in benches:
        entries = []
        for job in harness.arms_for(bench['ports']):
            if job['lang'] != 'selka' and job['arm'] != 'zig-fast':
                continue
            if args.mode == 'zero-rc' and job['lang'] == 'selka':
                job['flags'] = [*job['flags'], '--experimental-zero-rc']
            job['bench'] = bench['name']
            job['bin'] = work / f"{bench['name']}-{job['arm']}"
            built = harness.build(job, tools, work)
            if not built['ok']:
                raise RuntimeError(f"build {bench['name']} {job['arm']}: {built['stderr']}")
            stdout, stderr = command([job['bin']])
            if stdout != bench['expected'] or stderr:
                raise ValueError(f"parity output mismatch: {bench['name']} {job['arm']}")
            entries.append(job)
        jobs[bench['name']] = entries
        report['benchmarks'][bench['name']] = {
            'group': bench['group'], 'arms': {job['arm']: {'seconds': []} for job in entries}}
        print('built and checked', bench['name'], flush=True)
    report['load_start'] = os.getloadavg()
    rng = random.Random(20261015)
    for round_index in range(args.rounds):
        for bench in benches:
            ordered = list(jobs[bench['name']])
            rng.shuffle(ordered)
            for job in ordered:
                start = time.monotonic()
                stdout, stderr = command([job['bin']], timeout=600)
                seconds = time.monotonic() - start
                if stdout != bench['expected'] or stderr:
                    raise ValueError(f"parity output mismatch: {bench['name']} {job['arm']}")
                report['benchmarks'][bench['name']]['arms'][job['arm']]['seconds'].append(seconds)
            save(work, report)
        print('parity round', round_index + 1, 'complete', flush=True)
    report['load_end'] = os.getloadavg()
    for bench in report['benchmarks'].values():
        ref = bench['arms'].get('zig-fast', {}).get('seconds')
        for arm in bench['arms'].values():
            arm['median_seconds'] = statistics.median(arm['seconds'])
            arm['paired_ratios'] = [value / base for value, base in zip(arm['seconds'], ref)] if ref else None
            arm['median_ratio'] = statistics.median(arm['paired_ratios']) if ref else None
    save(work, report)
    return report


def runtime(args, work):
    directory = ROOT / 'benchmarks/runtime'
    registry = module_at('ownership_runtime', directory / 'expanded/registry.py')
    historical = json.loads((directory / 'expanded/results/baseline_main_20261003.json').read_text())
    plans = historical['plans']
    if len(plans) != 80 or len({plan['case'] for plan in plans}) != 40:
        raise ValueError('runtime baseline does not cover 40 cases at two sizes')
    if set(registry.inventory()) != {plan['case'] for plan in plans}:
        raise ValueError('runtime case inventory changed')
    for plan in plans:
        if plan['expected'] != registry.checksum(plan['case'], plan['size'], plan['iterations'], plan['seed']):
            raise ValueError(f"historical oracle mismatch: {plan['case']}")
    clock = directory / 'ports/native_clock.c'
    binaries = {}
    flags = ['--experimental-zero-rc'] if args.mode == 'zero-rc' else []
    for group in registry.GROUPS:
        source = directory / 'ports' if group == 'legacy' else directory / 'expanded' / group
        binary = work / group
        command([args.compiler, 'build', source / 'main.selka', '--release', *flags,
                 '--link', clock, '--cache-dir', work / 'cache', '-o', binary])
        binaries[group] = binary
        print('built runtime', group, flush=True)
    report = {'suite': 'runtime', 'rounds': args.rounds, 'mode': args.mode,
              'load_start': os.getloadavg(), 'rows': []}
    for plan in plans:
        samples = []
        for round_index in range(args.rounds):
            start = time.monotonic()
            stdout, stderr = command([binaries[plan['group']], plan['case'], plan['size'],
                                      plan['iterations'], plan['seed']], timeout=600)
            seconds = time.monotonic() - start
            fields = stdout.split()
            if stderr or len(fields) != 2 or int(fields[0]) != plan['expected'] or int(fields[1]) <= 0:
                raise ValueError(f"runtime output mismatch: {plan['case']} {plan['size']}: {stdout!r}, {stderr!r}")
            samples.append({'kernel_ns': int(fields[1]), 'wall_seconds': seconds})
        row = {key: plan[key] for key in ('case', 'size', 'iterations', 'seed', 'unit', 'group')}
        row['samples'] = samples
        row['ns_per_iteration'] = statistics.median(sample['kernel_ns'] for sample in samples) / plan['iterations']
        previous = next(summary['median_ns_per_op'] for summary in historical['summary']
                        if summary['case'] == plan['case'] and summary['size'] == plan['size']
                        and summary['arm'] == 'my-llvm')
        row['historical_ratio'] = row['ns_per_iteration'] / previous
        report['rows'].append(row)
        save(work, report)
        print('runtime', plan['case'], plan['size'], 'pass', flush=True)
    report['load_end'] = os.getloadavg()
    save(work, report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--zig', required=True, type=Path)
    parser.add_argument('--suite', choices=('parity', 'runtime'), required=True)
    parser.add_argument('--mode', choices=('default', 'zero-rc'), default='default')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--work', required=True, type=Path)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error('--rounds must be positive')
    args.compiler = args.compiler.resolve(strict=True)
    args.zig = args.zig.resolve(strict=True)
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    os.environ.update(SELKA_COMPILER_SHARED_CACHE='', SELKA_TEST_SHARED_CACHE='',
                      SELKA_CORE_RUNTIME_CACHE=str(work / 'runtime-cache'))
    for key in ('SELKA_COUNTERS', 'SELKA_CORE_LEAKCHECK', 'SELKA_OPTIONS'):
        os.environ.pop(key, None)
    (parity if args.suite == 'parity' else runtime)(args, work)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
