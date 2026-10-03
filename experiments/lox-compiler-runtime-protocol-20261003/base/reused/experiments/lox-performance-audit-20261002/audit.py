#!/usr/bin/env python3
"""Pinned Lox audit: verify outputs, interleave timings, and count instructions.

Binaries and source inputs live in the private --work directory. The binary
manifest supplies absolute paths; no benchmark source or existing cache is edited.
Each completed sample is saved, including input/output and executable hashes.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import signal
import statistics
import subprocess
import time


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def clean_env():
    return {k: v for k, v in os.environ.items()
            if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}


def run(command, env, timeout):
    started = time.perf_counter()
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError(f'timeout after {timeout}s: {command}')
    return {'wall_s': time.perf_counter() - started, 'status': process.returncode,
            'stdout': stdout, 'stderr': stderr}


def cpu_state():
    result = {}
    for line in Path('/proc/stat').read_text().splitlines():
        fields = line.split()
        if fields and fields[0].startswith('cpu') and fields[0][3:].isdigit():
            values = list(map(int, fields[1:]))
            result[int(fields[0][3:])] = (sum(values[:8]), values[3] + values[4])
    return result


def siblings(cpu):
    text = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list').read_text()
    result = []
    for piece in text.strip().split(','):
        start, _, end = piece.partition('-')
        result.extend(range(int(start), int(end or start) + 1))
    return result


def quiet(cpu, waits, deadline=120):
    started = time.monotonic()
    while True:
        before = cpu_state()
        time.sleep(0.4)
        after = cpu_state()
        busy = {c: 1 - (after[c][1] - before[c][1]) /
                max(1, after[c][0] - before[c][0]) for c in siblings(cpu)}
        if max(busy.values()) < 0.25:
            waits.append({'seconds': time.monotonic() - started, 'busy': busy})
            return
        if time.monotonic() - started > deadline:
            raise RuntimeError(f'timing CPU {cpu} remained busy: {busy}')
        time.sleep(1)


def cases(work, tier, engines, selected):
    bench = work / 'reference/benchmarks/lox/bench'
    sizes = json.loads((bench / 'sizes.json').read_text())
    scripts = work / 'inputs'
    scripts.mkdir(exist_ok=True)
    for engine in engines:
        for source in sorted((bench / 'scripts').glob('*.lox')):
            name = source.stem
            if selected and name not in selected:
                continue
            key = engine if tier == 'timed' else tier
            size = sizes[name][key]
            first, rest = source.read_text().split('\n', 1)
            assert first.startswith('var N = '), source
            path = scripts / f'{name}.{key}.lox'
            content = f'var N = {size};\n{rest}'
            if not path.exists() or path.read_text() != content:
                path.write_text(content)
            yield {'id': f'{engine}/{name}', 'engine': engine, 'name': name,
                   'size': size, 'script': str(path), 'script_sha256': sha(path),
                   'expected': str(bench / 'expected' / f'{name}.{key}.out')}


def checked(result, case):
    assert result['status'] == 0, (case['id'], result['status'], result['stderr'][-1000:])
    assert result['stdout'] == Path(case['expected']).read_bytes(), (
        case['id'], result['stdout'][:400], Path(case['expected']).read_bytes()[:400])
    return {'status': result['status'], 'stdout_sha256': hashlib.sha256(result['stdout']).hexdigest(),
            'stderr': result['stderr'].decode(errors='replace')[-1500:]}


def summary(doc):
    rows = {}
    for sample in doc['samples']:
        key = sample['case']
        row = rows.setdefault(key, {})
        arm = sample['arm']
        row.setdefault(arm, []).append(sample)
    result = {}
    for key, arms in rows.items():
        row = {}
        for arm, samples in arms.items():
            values = [s['wall_s'] for s in samples]
            median = statistics.median(values)
            value = {'wall_s': median,
                     'wall_spread': (max(values) - min(values)) / median,
                     'samples': len(samples)}
            for counter in ('instructions', 'cycles', 'branches', 'branch-misses', 'maxrss_kib'):
                counts = [s[counter] for s in samples if counter in s]
                if counts:
                    value[counter] = statistics.median(counts)
            if 'instructions' in value and 'cycles' in value:
                value['ipc'] = value['instructions'] / value['cycles']
            row[arm] = value
        if 'zig' in row:
            for value in row.values():
                value['wall_vs_zig'] = value['wall_s'] / row['zig']['wall_s']
                if 'instructions' in value and 'instructions' in row['zig']:
                    value['instructions_vs_zig'] = value['instructions'] / row['zig']['instructions']
        result[key] = row
    doc['summary'] = result
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['check', 'time', 'counters', 'rss'])
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--arms', default='mylang-llvm,mylang-qbe,zig,rust,go')
    parser.add_argument('--engines', default='vm,tree')
    parser.add_argument('--cases', default='')
    parser.add_argument('--tier', choices=['timed', 'tree', 'smoke'], default='timed')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--stats', action='store_true', help='Compare the Lox collector work across arms')
    args = parser.parse_args()
    work = args.work.resolve()
    binary_manifest = json.loads((work / 'binaries.json').read_text())
    arms = args.arms.split(',')
    binaries = {arm: Path(binary_manifest['binaries'][arm]) for arm in arms}
    hashes = {arm: sha(binary) for arm, binary in binaries.items()}
    selected = set(filter(None, args.cases.split(',')))
    inputs = list(cases(work, args.tier, args.engines.split(','), selected))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    env = clean_env()
    doc = {'phase': args.phase, 'tier': args.tier, 'cpu': args.cpu,
           'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'manifest': binary_manifest, 'binary_sha256': hashes,
           'cases': inputs, 'samples': [], 'quiet_waits': [], 'rounds': args.rounds}
    rng = random.Random(20261002)
    for round_index in range(args.rounds):
        for case in inputs:
            collector_stats = []
            order = list(arms)
            rng.shuffle(order)
            quiet(args.cpu, doc['quiet_waits'])
            for arm in order:
                command = [str(binaries[arm]), f"--engine={case['engine']}", case['script']]
                if args.stats:
                    command.insert(2, '--stats')
                report = work / 'tmp' / 'measurement.txt'
                if args.phase == 'counters':
                    command = ['perf', 'stat', '-x,', '-o', str(report), '-e',
                               'instructions:u,cycles:u,branches:u,branch-misses:u', '--', *command]
                elif args.phase == 'rss':
                    command = ['/usr/bin/time', '-o', str(report), '-f', '%M', *command]
                result = run(['taskset', '-c', str(args.cpu), *command], env, args.timeout)
                sample = {'case': case['id'], 'arm': arm, 'round': round_index,
                          'wall_s': result['wall_s'], **checked(result, case)}
                if args.stats:
                    stats = {k: int(v) for k, v in re.findall(
                        r'(allocations|collections|freed|live)=(\d+)', sample['stderr'])}
                    assert len(stats) == 4, ('missing Lox stats', sample)
                    sample['collector_stats'] = stats
                    collector_stats.append(stats)
                if args.phase == 'counters':
                    for line in report.read_text().splitlines():
                        fields = line.split(',')
                        if len(fields) < 3 or not fields[0].strip().isdigit():
                            continue
                        event = fields[2].strip()
                        event = event.split('/')[1] if '/' in event else event.split(':')[0]
                        for name in ('instructions', 'cycles', 'branches', 'branch-misses'):
                            if name == event:
                                assert name not in sample, ('multiple PMUs counted', name, line)
                                sample[name] = int(fields[0].strip())
                                if len(fields) > 4 and fields[4].strip():
                                    sample[name + '_running_pct'] = float(fields[4])
                    assert all(name in sample for name in ('instructions', 'cycles', 'branches', 'branch-misses')), sample
                elif args.phase == 'rss':
                    sample['maxrss_kib'] = int(report.read_text().strip())
                doc['samples'].append(sample)
                save(args.out, doc)
            if args.stats:
                assert all(stats == collector_stats[0] for stats in collector_stats), (
                    'Lox collector work differs between ports', case['id'], collector_stats)
            print(f"{args.phase} round {round_index + 1} {case['id']} N={case['size']}: " +
                  ', '.join(f"{s['arm']} {s['wall_s']:.3f}s" for s in doc['samples'][-len(arms):]), flush=True)
    for arm, binary in binaries.items():
        assert sha(binary) == hashes[arm], ('binary changed during measurements', arm)
    for case in inputs:
        assert sha(case['script']) == case['script_sha256'], ('script changed during measurements', case['id'])
    rows = summary(doc)
    doc['verified_after'] = True
    doc['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save(args.out, doc)
    for engine in args.engines.split(','):
        for arm in arms:
            ratios = [r[arm]['wall_vs_zig'] for key, r in rows.items()
                      if key.startswith(engine + '/') and 'wall_vs_zig' in r[arm]]
            if ratios:
                gm = math.exp(statistics.mean(math.log(v) for v in ratios))
                print(engine, arm, f'wall/Zig geomean {gm:.3f}x', flush=True)


if __name__ == '__main__':
    main()
