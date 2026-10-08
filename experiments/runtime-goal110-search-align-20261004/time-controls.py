#!/usr/bin/env python3
"""Three retained text artifacts at the exact six-arm screen calibration."""
import argparse
from datetime import datetime, timezone
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
parser.add_argument('join5a_directory', type=Path)
parser.add_argument('parser52_directory', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
screen = json.loads(args.screen.read_text())
assert screen['status'] == 'subset' and screen['rounds'] == 5 and screen['warmup_rounds'] == 1
binaries = {}
for backend in ('llvm', 'qbe'):
    binaries['join5a-' + backend] = args.join5a_directory / ('text-my-' + backend)
    binaries['parser52-' + backend] = args.parser52_directory / ('text-my-' + backend)
    binaries['aligned570-' + backend] = Path(screen['identity']['binary_paths']['text/my-' + backend])
for name, binary in binaries.items():
    manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
    assert manifest['backend'] == name.rsplit('-', 1)[1]
    if manifest['backend'] == 'llvm':
        assert str(manifest['optimization']) == '3' and manifest['lto']
hashes = {name: runner.digest(path) for name, path in binaries.items()}
started = datetime.now(timezone.utc).isoformat()
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
    for target in (Path('/sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq'),
                   Path('/sys/devices/system/cpu/cpu2/thermal_throttle/core_throttle_count'),
                   Path('/sys/devices/system/cpu/cpu2/thermal_throttle/package_throttle_count')):
        if target.exists():
            records[str(target)] = target.read_text().strip()
    return records


rows = []
for plan in screen['plans']:
    samples = []
    for round_index in range(-1, 5):
        arms = list(binaries)
        random.Random(f"{plan['case']}/{plan['profile']}/{round_index}").shuffle(arms)
        for arm in arms:
            before = host_counters()
            samples.append({'round': round_index, 'arm': arm,
                            **runner.invoke(binaries[arm], plan['case'], plan['size'],
                                            plan['iterations'], plan['seed'], 2, plan['expected']),
                            'host_before': before, 'host_after': host_counters()})
    medians = {arm: statistics.median(sample['kernel_ns'] / plan['iterations']
                                     for sample in samples if sample['round'] >= 0 and sample['arm'] == arm)
               for arm in binaries}
    ratios = {comparison: {backend: medians[after + '-' + backend] / medians[before + '-' + backend]
                          for backend in ('llvm', 'qbe')}
              for comparison, after, before in (('aligned570/parser52', 'aligned570', 'parser52'),
                                                ('aligned570/join5a', 'aligned570', 'join5a'),
                                                ('parser52/join5a', 'parser52', 'join5a'))}
    rows.append({'plan': plan, 'samples': samples, 'medians_ns_per_op': medians,
                 'after_before_ratios': ratios})
    print(plan['case'], plan['profile'], ratios, flush=True)
assert hashes == {name: runner.digest(path) for name, path in binaries.items()}
args.output.write_text(json.dumps({'status': 'complete', 'kind': 'exploratory three-artifact MyLang text comparison',
                                 'six_arm_screen': str(args.screen), 'six_arm_screen_sha256': runner.digest(args.screen),
                                 'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(),
                                 'binary_hashes_before_after': hashes,
                                 'binaries': {name: str(path) for name, path in binaries.items()},
                                 'environment': runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()),
                                 'rounds': 5, 'warmups': 1, 'rows': rows,
                                 'script_sha256': runner.digest(Path(__file__)),
                                 'limit': 'A function alignment attribute also changes whole text section placement. '
                                 'These ratios evaluate the full artifact change, not scanner-only causality. '
                                 'Cgroup counters cover all processes; frequency reads are snapshots.'}, indent=2) + '\n')
