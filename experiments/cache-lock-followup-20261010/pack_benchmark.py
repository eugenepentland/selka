#!/usr/bin/env python3
"""Prepare outside timing admission, then compare identical packed-store workloads."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def cases(rounds, sizes):
    for size in sizes:
        for mode in ('refresh', 'contend'):
            for round_ in range(rounds):
                arms = ('baseline', 'candidate') if round_ % 2 == 0 else ('candidate', 'baseline')
                for arm in arms:
                    yield {'name': f'{size}-{mode}-{round_}-{arm}', 'packs': size,
                           'mode': mode, 'round': round_, 'arm': arm,
                           'iterations': 32 if mode == 'refresh' else 64}


def parse_locks(text):
    """Join strace unfinished calls; report observed sequence flock-to-close spans."""
    pending, held = {}, {}
    waits, holds = [], []
    for line in text.splitlines():
        match = re.match(r'\s*(\d+)\s+(\d+\.\d+)\s+(.*)', line)
        if not match:
            continue
        pid, stamp, body = match.groups()
        stamp = float(stamp)
        if '<unfinished ...>' in body:
            pending[pid] = (stamp, body.split('<unfinished ...>')[0])
            continue
        if body.startswith('<... '):
            if pid not in pending:
                raise ValueError('resumed syscall without entry')
            stamp, prefix = pending.pop(pid)
            body = prefix + body.split('resumed>', 1)[1].lstrip()
        call = re.match(r'(flock|close)\((\d+)<[^>]+/sequence>(.*)', body)
        if not call:
            continue
        duration = re.search(r'<([0-9.]+)>$', body)
        if not duration or not re.search(r'= 0\s+<', body):
            continue
        operation, fd, rest = call.groups()
        seconds = float(duration[1])
        descriptor = (pid, fd)
        if operation == 'flock' and 'LOCK_EX' in rest:
            if descriptor in held:
                raise ValueError('duplicate acquired descriptor')
            waits.append(seconds)
            held[descriptor] = stamp + seconds
        elif operation == 'close' and descriptor in held:
            holds.append(max(0.0, stamp - held.pop(descriptor)))
    if held:
        raise ValueError('acquired descriptors without observed close')
    def summarize(values):
        return {'count': len(values), 'sum_s': sum(values),
                'median_s': statistics.median(values) if values else None,
                'max_s': max(values) if values else None}
    return {'flock_syscall': summarize(waits), 'held_until_close': summarize(holds),
            'method': 'Intrusive strace diagnostic; holds start at successful flock return and end before close. '
                      'Sums over workers are resource occupancy, not elapsed time.'}


def prepare(args, binaries):
    args.output.mkdir(parents=True, exist_ok=False)
    plan = list(cases(args.rounds, args.sizes))
    for size in args.sizes:
        seed = args.output / f'seed-{size}'
        result = subprocess.run([str(binaries['baseline']), 'seed', str(seed), str(size)],
                                text=True, capture_output=True, check=True)
        write(args.output / f'seed-{size}.json', json.loads(result.stdout))
        if len(list(seed.glob('*.pack'))) != size:
            raise ValueError('unexpected seed pack count')
        for case in plan:
            if case['packs'] == size:
                shutil.copytree(seed, args.output / case['name'])
    for arm in binaries:
        shutil.copytree(args.output / f'seed-{args.sizes[0]}', args.output / f'trace-{arm}')
    write(args.output / 'plan.json', {'cases': plan, 'binaries': {
        name: {'path': str(path), 'sha256': digest(path)} for name, path in binaries.items()},
        'method': 'Fixed identity and seed bytes isolate storage implementation changes. '
                  'Independent copies for every arm/case; seeding, copying and compilation precede timing admission. '
                  'Priming catalog scans precede work_ns; process wall and maximum-process RSS include startup, '
                  'priming, verification and deinitialization. Four publisher threads share the selected CPUs.'})


def run(args, binaries):
    if (args.output / 'results.json').exists():
        raise ValueError('measurement output already exists; prepare fresh stores')
    plan = json.loads((args.output / 'plan.json').read_text())
    for name, path in binaries.items():
        if plan['binaries'][name]['sha256'] != digest(path):
            raise ValueError('binary changed after preparation')
    results = []
    for case in plan['cases']:
        stem = args.output / case['name']
        command = ['/usr/bin/time', '-f', '{"rss_kib":%M,"user_s":%U,"system_s":%S,"exit":%x}',
                   '-o', str(stem.with_suffix('.time.json')), str(binaries[case['arm']]),
                   case['mode'], str(stem), str(case['iterations'])]
        started = time.monotonic()
        result = subprocess.run(command, text=True, capture_output=True, check=True)
        elapsed = time.monotonic() - started
        metrics = json.loads(stem.with_suffix('.time.json').read_text().splitlines()[-1])
        measured = json.loads(result.stdout)
        if not measured['verified']:
            raise ValueError('workload did not verify results')
        entry = dict(case, **measured, **metrics, process_wall_s=elapsed)
        results.append(entry)
        write(args.output / 'results.json', {'plan': plan, 'results': results})
        print(json.dumps(entry), flush=True)
    diagnostics = {}
    for arm, binary in binaries.items():
        trace = args.output / f'{arm}.strace'
        result = subprocess.run(['strace', '-f', '-ttt', '-T', '-yy', '-e', 'trace=flock,close',
                                 '-o', str(trace), str(binary), 'contend',
                                 str(args.output / f'trace-{arm}'), '16'],
                                text=True, capture_output=True, check=True)
        diagnostics[arm] = dict(parse_locks(trace.read_text()), result=json.loads(result.stdout),
                                trace_sha256=digest(trace))
        if not diagnostics[arm]['held_until_close']['count']:
            raise ValueError('no completed lock holds in trace')
    write(args.output / 'lock-diagnostics.json', diagnostics)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('prepare', 'run'))
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--sizes', type=int, nargs='+', default=[128, 3500])
    args = parser.parse_args()
    args.output = args.output.resolve()
    binaries = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    if args.rounds < 1 or min(args.sizes) < 1:
        parser.error('positive rounds and sizes required')
    (prepare if args.phase == 'prepare' else run)(args, binaries)


if __name__ == '__main__':
    main()
