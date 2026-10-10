#!/usr/bin/env python3
"""Build and compare U2 checkpoints with unchanged workloads and references."""
import argparse
import collections
import gzip
import json
import os
from pathlib import Path
import random
import statistics
import sys
import time

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import ce
import pstat


def require_slot():
    lock = Path(os.readlink('/proc/self/fd/9'))
    if not lock.name.startswith('build') or lock.suffix != '.lock':
        raise RuntimeError('Run through scripts/build-slot.sh build')


def build(args):
    lane = ce.Lane(args.compiler, args.tag)
    lane.bins.mkdir(parents=True, exist_ok=True)
    groups = [('lox', ce.LOX_SRC / 'main.my', ce.LOX_SRC)]
    if args.eda:
        groups.append(('eda', ce.EDA_SRC / 'src/main.my', ce.EDA_SRC))
    hashes = {}
    durations = {}
    for name, source, cwd in groups:
        for kind in ('plain', 'count'):
            output = lane.bins / f'{name}-{kind}'
            command = [lane.compiler, 'build', source, '-o', output, '--cache-dir', lane.cache, '--release']
            if kind == 'count':
                command.append('--counters')
            began = time.monotonic()
            status, stdout, stderr = ce.run(command, cwd=cwd, slot=False,
                                            extra_env={'MYLANG_CORE_RUNTIME_CACHE': str(lane.runtime_cache)})
            durations[output.name] = time.monotonic() - began
            if status:
                raise RuntimeError(f'{name}/{kind}: {status}: {stderr.decode()[-5000:]}')
            hashes[output.name] = ce.digest(output)
            print('built', output, flush=True)
    args.out.write_text(json.dumps({'tag': args.tag, 'compiler_sha256': ce.digest(args.compiler), 'binaries': hashes, 'seconds': durations}, indent=1) + '\n')


def cases(tag):
    binary = ce.CACHE / 'bin' / tag / 'lox-plain'
    sizes = json.loads((ce.LOX / 'bench/sizes.json').read_text())
    return [{'program': f'lox/{engine}/{name}', 'arm': tag, 'cwd': str(ce.LOX),
             'argv': [str(binary), '--engine=' + engine, str(ce.lox_script(name, sizes[name][engine]))]}
            for engine, name in [('vm', 'invocation'), ('vm', 'fib'), ('vm', 'method_call'), ('tree', 'equality')]]


def measure(args):
    arms = cases('base') + cases(args.tag)
    rng = random.Random(20261010)
    samples = collections.defaultdict(list)
    for _ in range(3):
        rng.shuffle(arms)
        for arm in arms:
            sample = pstat.run_once(arm, 8)
            if sample['status'] or not sample.get('instructions'):
                raise RuntimeError(str(sample))
            samples[(arm['program'], arm['arm'])].append(sample)
    rows = []
    for program in sorted({a['program'] for a in arms}):
        medians = {tag: {event: statistics.median(row[event] for row in samples[(program, tag)] if row.get(event) is not None)
                         for event in pstat.EVENTS} for tag in ('base', args.tag)}
        rows.append({'program': program, 'median': medians,
                     'ratio': {event: medians[args.tag][event] / medians['base'][event] if medians['base'][event] else None for event in pstat.EVENTS},
                     'samples': {tag: samples[(program, tag)] for tag in ('base', args.tag)}})
    args.out.write_text(json.dumps({'cpu': 8, 'rounds': 3, 'tag': args.tag, 'rows': rows}, indent=1) + '\n')
    for row in rows:
        print(row['program'], row['ratio']['instructions'], row['ratio']['cycles'], flush=True)


def counts(args):
    lane = ce.Lane(args.compiler, args.tag)
    sizes = json.loads((ce.LOX / 'bench/sizes.json').read_text())
    rows = []
    for name in ('invocation', 'method_call'):
        n = sizes[name]['vm']
        script = ce.lox_script(name, n)
        label = f'lox:vm-{name}-{n}'
        result = lane.counted_run(label, lambda counting: ['--engine=vm', script], ce.CACHE, 1800)
        if not result['same_output'] or result['status']:
            raise RuntimeError(str(result))
        key = label.replace(':', '-')
        raw = json.loads(gzip.open(lane.raw / (key + '.json.gz'), 'rt').read())
        calls = sum(f['calls'] for f in raw['functions'] if f['name'] in ('vm::read_constant', 'vm::read_string'))
        traffic = {kind: sum(site['count'] for site in raw['sites'] if site.get('origin') == 'vm::read_constant' and site['kind'] == kind)
                   for kind in ('retain', 'release')}
        frame_sites = [site for site in raw['sites'] if site['kind'] == 'record_copy' and site['bytes'] and
                       ((site['function'] == 'vm::run' and site['path'] == 'vm.my' and site['line'] in (430, 496, 503, 510, 525)) or
                        (site['function'] == 'vm::call' and site['path'] == 'vm.my' and site['line'] == 135))]
        rows.append({'label': key, 'output': result, 'read_constant_executions': calls, **traffic,
                     'frame_copy_bytes': sum(s['bytes'] for s in frame_sites), 'frame_copy_sites': frame_sites,
                     'all_record_copy_bytes': sum(s['bytes'] for s in raw['sites'] if s['kind'] == 'record_copy')})
        print(key, calls, traffic, rows[-1]['frame_copy_bytes'], flush=True)
    args.out.write_text(json.dumps({'tag': args.tag, 'rows': rows}, indent=1) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['build', 'measure', 'counts'])
    parser.add_argument('--tag', required=True)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--eda', action='store_true')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    require_slot()
    globals()[args.action](args)


if __name__ == '__main__':
    main()
