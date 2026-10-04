#!/usr/bin/env python3
"""Exploratory current-source pairs using freshly calibrated six-arm plans."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import random
import statistics
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
import runner
from build_compiler import validate_receipt
from compare_candidate import bootstrap
from registry import checksum

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--plans', type=Path, required=True)
parser.add_argument('--before-manifest', type=Path, required=True)
parser.add_argument('--after-manifest', type=Path, required=True)
parser.add_argument('--rounds', type=int, default=5)
parser.add_argument('--warmups', type=int, default=1)
parser.add_argument('--cpu', type=int, default=2)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert args.rounds > 0 and args.warmups >= 0 and args.cpu in os.sched_getaffinity(0)
screen = json.loads(args.plans.read_text())
assert screen['status'] == 'subset'
plans = screen['plans']
assert len(plans) == 8 and {plan['case'] for plan in plans} == {
    'mutate_unique', 'mutate_shared', 'record_reads', 'tagged_stack'}
for plan in plans:
    assert plan['expected'] == checksum(plan['case'], plan['size'], plan['iterations'], plan['seed'])

manifests, binaries, hashes, sidecars = {}, {}, {}, {}
for arm, path in (('before', args.before_manifest), ('candidate', args.after_manifest)):
    manifest = json.loads(path.read_text())
    receipt = manifest['identity']['compiler_build_receipt']['receipt']
    validate_receipt(receipt, receipt['compiler_path'], artifacts=True)
    assert receipt['compiler_optimize'] == 'Debug'
    manifests[arm] = {'path': str(path.resolve()), 'sha256': runner.digest(path),
                      'source_revision': manifest['identity']['source_revision'],
                      'compiler_build_receipt': manifest['identity']['compiler_build_receipt']}
    for backend in ('llvm', 'qbe'):
        key = arm + '-' + backend
        name = 'legacy/my-' + backend
        binaries[key] = Path(manifest['identity']['binary_paths'][name])
        hashes[key] = runner.digest(binaries[key])
        assert hashes[key] == manifest['binary_hashes'][name]
        path = Path(str(binaries[key]) + '.qbe-manifest.json')
        sidecar = json.loads(path.read_text())
        assert sidecar['backend'] == backend
        assert backend != 'llvm' or (str(sidecar['optimization']) == '3' and sidecar['lto'])
        sidecars[key] = runner.digest(path)
assert manifests['candidate']['source_revision'] == screen['identity']['source_revision']


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
    for name in ('cpufreq/scaling_cur_freq', 'thermal_throttle/core_throttle_count',
                 'thermal_throttle/package_throttle_count'):
        target = Path(f'/sys/devices/system/cpu/cpu{args.cpu}') / name
        if target.exists():
            records[str(target)] = target.read_text().strip()
    return records


started = datetime.now(timezone.utc).isoformat()
cpu_before = runner.cpu_snapshot()
rows = []
for plan in plans:
    samples = []
    for round_index in range(-args.warmups, args.rounds):
        arms = list(binaries)
        random.Random(f"unique-capture/{plan['case']}/{plan['profile']}/{round_index}").shuffle(arms)
        for arm in arms:
            host_before = host_counters()
            samples.append({'round': round_index, 'arm': arm,
                            **runner.invoke(binaries[arm], plan['case'], plan['size'], plan['iterations'],
                                            plan['seed'], args.cpu, plan['expected']),
                            'host_before': host_before, 'host_after': host_counters()})
    values = {arm: [sample['kernel_ns'] for sample in samples
                    if sample['round'] >= 0 and sample['arm'] == arm] for arm in binaries}
    medians = {arm: statistics.median(value) / plan['iterations'] for arm, value in values.items()}
    comparisons = {backend: {
        'candidate_to_before': medians['candidate-' + backend] / medians['before-' + backend],
        'paired_bootstrap_95_interval': bootstrap(values['candidate-' + backend], values['before-' + backend],
                                                  f"unique-capture/{plan['case']}/{plan['profile']}/{backend}")}
        for backend in ('llvm', 'qbe')}
    rows.append({'plan': plan, 'samples': samples, 'medians_ns_per_iteration': medians,
                 'comparisons': comparisons})
    print(plan['case'], plan['profile'], comparisons, flush=True)
assert hashes == {key: runner.digest(path) for key, path in binaries.items()}
assert sidecars == {key: runner.digest(Path(str(path) + '.qbe-manifest.json')) for key, path in binaries.items()}
report = {'status': 'complete', 'kind': 'exploratory-paired-unique-capture-screen',
          'measurement_session_id': str(uuid.uuid4()), 'started_utc': started,
          'finished_utc': datetime.now(timezone.utc).isoformat(),
          'manifests': manifests, 'binary_hashes_before_after': hashes,
          'binary_manifest_hashes_before_after': sidecars,
          'binaries': {key: str(path) for key, path in binaries.items()},
          'six_arm_screen': {'path': str(args.plans.resolve()), 'sha256': runner.digest(args.plans)},
          'script_sha256': runner.digest(Path(__file__)),
          'environment': runner.cpu_environment(args.cpu, cpu_before, runner.cpu_snapshot()),
          'cpu': args.cpu, 'rounds': args.rounds, 'warmups': args.warmups, 'rows': rows,
          'limits': ['Exploratory screen; no acceptance or integrated-revision claim.',
                     'Both arms use source-bound Debug hosts and ReleaseFast guests; LLVM uses O3/full LTO.',
                     'Only fresh calibrated iteration/seed plans are reused; every paired sample is fresh.',
                     'Bootstrap intervals are uncorrected for selection and multiple comparisons.',
                     'Cgroup counters cover the whole group; frequency snapshots do not isolate guest throttling.']}
args.output.write_text(json.dumps(report, indent=2) + '\n')
