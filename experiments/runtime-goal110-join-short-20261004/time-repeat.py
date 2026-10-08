#!/usr/bin/env python3
"""Paired before/after MyLang guests at the exact six-arm screen calibration."""
from datetime import datetime, timezone
import uuid
import argparse
import json
from pathlib import Path
import random
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('screen', type=Path)
parser.add_argument('before_directory', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--rounds', type=int, default=15)
parser.add_argument('--warmups', type=int, default=3)
args = parser.parse_args()
screen_path, before_directory, output = args.screen, args.before_directory, args.output
screen = json.loads(screen_path.read_text())
assert screen['status'] == 'subset' and screen['rounds'] == 5 and screen['warmup_rounds'] == 1
binaries = {}
for backend in ('llvm', 'qbe'):
    binaries['before-' + backend] = before_directory / ('text-my-' + backend)
    binaries['after-' + backend] = Path(screen['identity']['binary_paths']['text/my-' + backend])
    for kind in ('before', 'after'):
        manifest = json.loads(Path(str(binaries[kind + '-' + backend]) + '.qbe-manifest.json').read_text())
        assert manifest['backend'] == backend
        if backend == 'llvm':
            assert str(manifest['optimization']) == '3' and manifest['lto']
hashes = {key: runner.digest(path) for key, path in binaries.items()}
started = datetime.now(timezone.utc).isoformat()
cpu_before = runner.cpu_snapshot()
rows = []

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
    for target in (Path('/sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq'),
                   Path('/sys/devices/system/cpu/cpu2/thermal_throttle/core_throttle_count'),
                   Path('/sys/devices/system/cpu/cpu2/thermal_throttle/package_throttle_count')):
        if target.exists():
            records[str(target)] = target.read_text().strip()
    return records

for plan in screen['plans']:
    if (plan['case'], plan['profile']) not in {('string_join', 'small'), ('string_join', 'large'), ('string_search', 'large')}:
        continue
    samples = []
    for round_index in range(-args.warmups, args.rounds):
        arms = list(binaries)
        random.Random(f"{plan['case']}/{plan['profile']}/{round_index}").shuffle(arms)
        for arm in arms:
            host_before = host_counters()
            samples.append({'round': round_index, 'arm': arm,
                            **runner.invoke(binaries[arm], plan['case'], plan['size'],
                                            plan['iterations'], plan['seed'], 2, plan['expected']),
                            'host_before': host_before, 'host_after': host_counters()})
    medians = {arm: statistics.median(sample['kernel_ns'] / plan['iterations']
                                     for sample in samples if sample['round'] >= 0 and sample['arm'] == arm)
               for arm in binaries}
    ratios = {backend: medians['after-' + backend] / medians['before-' + backend] for backend in ('llvm', 'qbe')}
    rows.append({'plan': plan, 'samples': samples, 'medians_ns_per_op': medians, 'after_before_ratios': ratios})
    print(plan['case'], plan['profile'], ratios, flush=True)
assert hashes == {key: runner.digest(path) for key, path in binaries.items()}
output.write_text(json.dumps({'status': 'complete', 'kind': 'independent focused Debug artifact repeat',
                              'measurement_session_id': str(uuid.uuid4()),
                              'six_arm_screen': str(screen_path), 'six_arm_screen_sha256': runner.digest(screen_path),
                              'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(),
                              'binary_hashes_before_after': hashes, 'binaries': {key: str(path) for key, path in binaries.items()},
                              'environment': runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()),
                              'rounds': args.rounds, 'warmups': args.warmups, 'rows': rows,
                              'script_sha256': runner.digest(Path(__file__)),
                              'host_counter_limit': 'Cgroup counters cover all processes in that group, and frequency reads are snapshots; neither isolates guest throttling or achieved frequency.'}, indent=2) + '\n')
