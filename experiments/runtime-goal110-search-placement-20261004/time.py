#!/usr/bin/env python3
"""Three-artifact placement sensitivity diagnostic; never goal acceptance."""
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
spec = importlib.util.spec_from_file_location('placement_validate', Path(__file__).with_name('validate.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
validate = module.validate

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--screen', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--rounds', type=int, default=15)
parser.add_argument('--warmups', type=int, default=3)
parser.add_argument('--cpu', type=int, default=2)
args = parser.parse_args()
assert not args.output.exists() and args.rounds == 15 and args.warmups == 3 and args.cpu == 2
binaries, artifacts_before = validate()
hashes = {name: runner.digest(path) for name, path in binaries.items()}
screen = json.loads(args.screen.read_text())
plans = [plan for plan in screen['plans'] if plan['case'] + '/' + plan['profile'] in
         ('string_equal/small', 'string_search/large')]
assert len(plans) == 2 and screen['status'] == 'subset'
report = {'kind': 'diagnostic-only placement sensitivity; no goal confirmation', 'status': 'running',
          'session_id': str(uuid.uuid4()), 'started_utc': datetime.now(timezone.utc).isoformat(),
          'screen': str(args.screen.resolve()), 'screen_sha256': runner.digest(args.screen),
          'rounds': args.rounds, 'warmups': args.warmups, 'cpu': args.cpu, 'rows': [],
          'binaries': artifacts_before['binaries'], 'binary_hashes': hashes,
          'artifacts_before': artifacts_before, 'script_sha256': runner.digest(Path(__file__)),
          'host_counter_limit': 'Cgroup counters include other group processes; frequency snapshots are not achieved guest frequencies.',
          'limitations': ['Later text placement also shifts; any recovery is placement sensitivity, not unique caller-address causality.',
                          'Private wrapper guest is not an official frozen runner arm or production candidate.']}
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
    cpu = Path('/sys/devices/system/cpu/cpu2')
    for name in ('cpufreq/scaling_cur_freq', 'thermal_throttle/core_throttle_count', 'thermal_throttle/package_throttle_count'):
        target = cpu / name
        if target.exists():
            records[str(target)] = target.read_text().strip()
    return records


print('START', report['session_id'], report['started_utc'], flush=True)
try:
    for plan in plans:
        key = plan['case'] + '/' + plan['profile']
        row = {'plan': plan, 'samples': []}
        report['rows'].append(row)
        for index in range(-args.warmups, args.rounds):
            order = list(binaries)
            random.Random('placement/' + key + '/' + str(index)).shuffle(order)
            for arm in order:
                command = ['taskset', '-c', str(args.cpu), str(binaries[arm]), plan['case'],
                           str(plan['size']), str(plan['iterations']), str(plan['seed'])]
                with runner.timing_lock():
                    before = host_counters()
                    started = time.perf_counter_ns()
                    done = subprocess.run(command, capture_output=True, text=True, timeout=120,
                                          env=runner.runtime_environment())
                    wall = time.perf_counter_ns() - started
                    after = host_counters()
                sample = {'round': index, 'arm': arm, 'command': command, 'status': done.returncode,
                          'stdout': done.stdout, 'stderr': done.stderr, 'process_wall_ns': wall,
                          'host_before': before, 'host_after': after}
                row['samples'].append(sample)
                sample.update(runner.validate(done, plan['expected']))
        medians = {arm: statistics.median(sample['kernel_ns'] / plan['iterations'] for sample in row['samples']
                                         if sample['round'] >= 0 and sample['arm'] == arm) for arm in binaries}
        row['medians_ns_per_op'] = medians
        row['ratios'] = {'annotation/g4': medians['annotation'] / medians['g4'],
                         'fill32/annotation': medians['fill32'] / medians['annotation'],
                         'fill32/g4': medians['fill32'] / medians['g4']}
        print(key, medians, row['ratios'], flush=True)
    _, report['artifacts_after'] = validate()
    assert hashes == {name: runner.digest(path) for name, path in binaries.items()}
    report['status'] = 'complete'
finally:
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    report['environment'] = runner.cpu_environment(args.cpu, cpu_before, runner.cpu_snapshot())
    args.output.write_text(json.dumps(report, indent=2) + '\n')
print('PASS108 complete diagnostic outcomes', report['finished_utc'], flush=True)
