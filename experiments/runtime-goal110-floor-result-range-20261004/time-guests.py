#!/usr/bin/env python3
"""Paired MyLang controls at six-arm plans; complete streams and host snapshots."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('screen', type=Path)
parser.add_argument('bindings', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--rounds', type=int, default=5)
parser.add_argument('--warmups', type=int, default=1)
parser.add_argument('--only', nargs='+', help='case/profile keys for a requested independent repeat')
args = parser.parse_args()
assert not args.output.exists() and args.rounds > 0 and args.warmups >= 0
spec = importlib.util.spec_from_file_location('live_bindings', Path(__file__).with_name('validate-live.py'))
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)
bindings = json.loads(args.bindings.read_text())
documents = live.validate(bindings)
screen = json.loads(args.screen.read_text())
assert screen['status'] == 'subset' and screen['rounds'] == 5 and screen['warmup_rounds'] == 1
assert screen['identity'] == documents['after']['identity']
binaries = {label + '-' + backend: Path(document['identity']['binary_paths']['text/my-' + backend])
            for label, document in documents.items() for backend in ('llvm', 'qbe')}
hashes = {key: runner.digest(path) for key, path in binaries.items()}
report = {'kind': 'exploratory Debug031 vs ReleaseFastG4 matched guest screen', 'status': 'running',
          'screen': str(args.screen.resolve()), 'screen_sha256': runner.digest(args.screen),
          'bindings': bindings, 'bindings_sha256': runner.digest(args.bindings), 'binary_hashes': hashes,
          'session_id': str(uuid.uuid4()), 'started_utc': datetime.now(timezone.utc).isoformat(),
          'rounds': args.rounds, 'warmups': args.warmups, 'cpu': 2, 'rows': [],
          'script_sha256': runner.digest(Path(__file__)),
          'host_counter_limit': 'Cgroup counters cover all group processes; frequency is a snapshot, not guest achieved frequency.'}
cpu_before = runner.cpu_snapshot()


def host_counters():
    records = {}
    relative = Path('/proc/self/cgroup').read_text().strip().split('::', 1)[1]
    path = Path('/sys/fs/cgroup') / relative.lstrip('/')
    while path.is_relative_to('/sys/fs/cgroup'):
        for name in ('cpu.stat', 'cpu.max'):
            target = path / name
            if target.exists():
                records[str(target)] = target.read_text().strip()
        if path == Path('/sys/fs/cgroup'):
            break
        path = path.parent
    directory = Path('/sys/devices/system/cpu/cpu2')
    for name in ('cpufreq/scaling_cur_freq', 'thermal_throttle/core_throttle_count', 'thermal_throttle/package_throttle_count'):
        target = directory / name
        if target.exists():
            records[str(target)] = target.read_text().strip()
    return records


try:
    for plan in screen['plans']:
        key = plan['case'] + '/' + plan['profile']
        if args.only and key not in args.only:
            continue
        row = {'plan': plan, 'samples': []}
        report['rows'].append(row)
        for round_index in range(-args.warmups, args.rounds):
            order = list(binaries)
            random.Random(key + '/' + str(round_index)).shuffle(order)
            for arm in order:
                command = ['taskset', '-c', '2', str(binaries[arm]), plan['case'], str(plan['size']),
                           str(plan['iterations']), str(plan['seed'])]
                with runner.timing_lock():
                    host_before = host_counters()
                    started = time.perf_counter_ns()
                    done = subprocess.run(command, capture_output=True, text=True, timeout=120, env=runner.runtime_environment())
                    wall = time.perf_counter_ns() - started
                    host_after = host_counters()
                sample = {'round': round_index, 'arm': arm, 'command': command, 'status': done.returncode,
                          'stdout': done.stdout, 'stderr': done.stderr, 'process_wall_ns': wall,
                          'host_before': host_before, 'host_after': host_after}
                row['samples'].append(sample)
                sample.update(runner.validate(done, plan['expected']))
        medians = {arm: statistics.median(sample['kernel_ns'] / plan['iterations'] for sample in row['samples']
                                         if sample['round'] >= 0 and sample['arm'] == arm) for arm in binaries}
        ratios = {backend: medians['after-' + backend] / medians['before-' + backend] for backend in ('llvm', 'qbe')}
        row.update(medians_ns_per_op=medians, after_before_ratios=ratios)
        print(key, ratios, flush=True)
    assert hashes == {key: runner.digest(path) for key, path in binaries.items()}
    live.validate(bindings)
    report['status'] = 'complete'
finally:
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    report['environment'] = runner.cpu_environment(2, cpu_before, runner.cpu_snapshot())
    args.output.write_text(json.dumps(report, indent=2) + '\n')
print('PASS matched guest controls with complete raw streams')
