#!/usr/bin/env python3
"""Interleaved, successful-only 200k check samples with independent caches."""
import argparse
import hashlib
import json
import os
import statistics
import shutil
import subprocess
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import measure


def records(cache):
    return {str(p.relative_to(cache)): p.stat().st_mtime_ns
            for p in cache.glob('modules/*/out/*.result.json')}


def one(side, cpus):
    before = records(side['cache'])
    result = measure.sample(side['command'], side['tree'], cpus)
    after = records(side['cache'])
    result['compiled_records'] = sum(before.get(name) != stamp for name, stamp in after.items())
    result['project_states'] = sum(not p.parent.name.startswith('standard-')
                                  for p in side['cache'].glob('modules/*/state.json'))
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('control', type=Path)
    p.add_argument('candidate', type=Path)
    p.add_argument('fixture', type=Path)
    p.add_argument('work', type=Path)
    p.add_argument('--json', required=True, type=Path)
    p.add_argument('--samples', type=int, default=7)
    p.add_argument('--cpus', default='2,3,10,11')
    p.add_argument('--candidate-revision', required=True)
    p.add_argument('--control-revision', required=True)
    args = p.parse_args()
    if args.samples < 3 or args.work.exists():
        p.error('at least three samples and a fresh work directory are required')
    args.work = args.work.resolve()
    args.work.mkdir(parents=True)
    sides = {}
    for name, compiler, revision in [('control', args.control, args.control_revision),
                                     ('candidate', args.candidate, args.candidate_revision)]:
        root = args.work / name
        tree = root / 'src'
        shutil.copytree(args.fixture, tree)
        cache = root / 'cache'
        sides[name] = {'tree': tree, 'cache': cache,
                       'command': [str(compiler.resolve()), 'check', 'main.my', f'--cache-dir={cache}'],
                       'compiler_sha256': measure.digest(compiler), 'revision': revision}
    result = {'fixture': measure.source_identity(args.fixture), 'cpus': args.cpus,
              'protocol': 'admission and edits outside clock; successful-only samples; independent caches; alternating first side; seeder settled before warm samples',
              'samples': args.samples, 'load_start': Path('/proc/loadavg').read_text(),
              'sides': {name: {key: value for key, value in side.items() if key not in ('tree', 'cache')}
                        for name, side in sides.items()}, 'cold': {}, 'phases': {}}
    def save():
        args.json.write_text(json.dumps(result, indent=1))
    for name in ('control', 'candidate'):
        result['cold'][name] = one(sides[name], args.cpus)
        save()
    expected = result['fixture']['files']
    result['candidate_seed_seconds'] = measure.settle(sides['candidate']['cache'], expected)
    save()
    for phase in ('noop', 'body', 'interface'):
        pairs = []
        result['phases'][phase] = {'pairs': pairs}
        for n in range(args.samples):
            if phase != 'noop':
                for side in sides.values():
                    modules = sorted(side['tree'].glob('m[0-9]*.my'))
                    measure.edit(modules[len(modules) // 2], n + 1, phase == 'interface')
            order = ('control', 'candidate') if n % 2 == 0 else ('candidate', 'control')
            pair = {'order': list(order), 'load': Path('/proc/loadavg').read_text()}
            for name in order:
                pair[name] = one(sides[name], args.cpus)
            if pair['control']['stdout_sha256'] != pair['candidate']['stdout_sha256']:
                raise RuntimeError('successful checks returned different stdout')
            if phase == 'noop' and pair['candidate']['compiled_records'] != 0:
                raise RuntimeError('no-op candidate compiled module records')
            if pair['candidate']['project_states'] != 1:
                raise RuntimeError('candidate did not use its per-module project state')
            pairs.append(pair)
            save()
        for name in sides:
            seconds = [row[name]['seconds'] for row in pairs]
            result['phases'][phase][name] = {'minimum_seconds': min(seconds),
                                           'median_seconds': statistics.median(seconds), 'seconds': seconds}
        save()
        print(phase, {name: result['phases'][phase][name]['median_seconds'] for name in sides}, flush=True)
    result['final_fixture_identity'] = {name: measure.source_identity(side['tree']) for name, side in sides.items()}
    if result['final_fixture_identity']['control'] != result['final_fixture_identity']['candidate']:
        raise RuntimeError('final paired sources differ')
    result['profiles'] = {}
    for name, side in sides.items():
        profile = subprocess.run(['taskset', '-c', args.cpus, 'strace', '-c'] + side['command'],
                                 cwd=side['tree'], capture_output=True, text=True, timeout=120)
        if profile.returncode != 0:
            raise RuntimeError(f'{name} warm profile failed: {profile.stderr}')
        result['profiles'][name] = {'status': profile.returncode, 'strace': profile.stderr,
                                    'stdout_sha256': hashlib.sha256(profile.stdout.encode()).hexdigest()}
    result['load_end'] = Path('/proc/loadavg').read_text()
    save()
    print(json.dumps({phase: {name: result['phases'][phase][name]['median_seconds']
                             for name in sides} for phase in result['phases']}, indent=1))


if __name__ == '__main__':
    main()
