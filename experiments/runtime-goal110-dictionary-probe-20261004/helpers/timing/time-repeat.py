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
from registry import checksum, inventory

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
assert len(plans) == 8 and {(p['case'],p['profile']) for p in plans} == {('dict_lookup', 'small'), ('dict_lookup_str', 'small'), ('dict_lookup_str', 'large'), ('dict_update_str', 'small'), ('dict_update', 'small'), ('dict_update', 'large'), ('dict_update_str', 'large'), ('set_dedup', 'small')}
original=screen['original_screen'];assert runner.digest(original['path'])==original['sha256']
original_report=json.loads(Path(original['path']).read_text());assert all(p in original_report['plans'] for p in plans)
assert screen['identity']==original_report['identity']
assert all(p['group']==inventory()[p['case']]['group'] for p in plans)
for plan in plans:
    assert plan['expected'] == checksum(plan['case'], plan['size'], plan['iterations'], plan['seed'])

manifests, binaries, hashes, sidecars = {}, {}, {}, {}
for arm, path in (('before', args.before_manifest), ('candidate', args.after_manifest)):
    manifest = json.loads(path.read_text())
    receipt = manifest['identity']['compiler_build_receipt']['receipt']
    validate_receipt(receipt, receipt['compiler_path'], artifacts=True)
    assert receipt['compiler_optimize'] == ('ReleaseFast' if arm == 'before' else 'Debug')
    manifests[arm] = {'path': str(path.resolve()), 'sha256': runner.digest(path),
                      'source_revision': manifest['identity']['source_revision'],
                      'compiler_build_receipt': manifest['identity']['compiler_build_receipt']}
    for group in ['legacy','collections','text']:
        for backend in ('llvm', 'qbe'):
            key = arm + '-' + group + '-' + backend
            name = group + '/my-' + backend
            binaries[key] = Path(manifest['identity']['binary_paths'][name])
            hashes[key] = runner.digest(binaries[key])
            assert hashes[key] == manifest['binary_hashes'][name]
            metadata_path = Path(str(binaries[key]) + '.qbe-manifest.json')
            sidecar = json.loads(metadata_path.read_text())
            assert sidecar['backend'] == backend
            assert backend != 'llvm' or (str(sidecar['optimization']) == '3' and sidecar['lto'] and not sidecar['thin_lto'])
            sidecars[key] = runner.digest(metadata_path)
assert manifests['before']['source_revision'] == '14ffa2c0f385a11e5216bbdec5bdff429f9f981b'
assert manifests['candidate']['source_revision'] == screen['identity']['source_revision'] == '64fb7e62732db9cea46414248fd59ba362e31b56'
assert manifests['before']['sha256'] == 'e02fd8476ee7b36d04e74a46287dcdbcc0fade79156f40b4e0de2d9e6674a171'
assert manifests['candidate']['sha256'] == 'f43a2e015585f9af90ee130df579f486d05e9afdd5d0380019cf6e45ef91f44e'
sys.path.insert(0,str(ROOT/'benchmarks/runtime/diagnostics'));import holdouts
for arm in ['before','candidate']:
 document=json.loads(Path(manifests[arm]['path']).read_text());holdouts.check_manifest(Path(manifests[arm]['path']),manifests[arm]['sha256'],document)


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
    selected_binaries = {arm+'-'+backend: binaries[arm+'-'+plan['group']+'-'+backend] for arm in ['before','candidate'] for backend in ['llvm','qbe']}
    for round_index in range(-args.warmups, args.rounds):
        arms = list(selected_binaries)
        random.Random(f"dictionary-probe/{plan['case']}/{plan['profile']}/{round_index}").shuffle(arms)
        for arm in arms:
            host_before = host_counters()
            samples.append({'round': round_index, 'arm': arm,
                            **runner.invoke(selected_binaries[arm], plan['case'], plan['size'], plan['iterations'],
                                            plan['seed'], args.cpu, plan['expected']),
                            'order':arms, 'host_before': host_before, 'host_after': host_counters()})
    rows.append({'plan': plan, 'samples': samples, 'binary_paths': {k:str(v) for k,v in selected_binaries.items()}})
    args.output.with_suffix('.progress.json').write_text(json.dumps({'status':'incomplete','plans':plans,'rows':rows},indent=2)+'\n')
    print(plan['case'],plan['profile'],'guest samples complete',flush=True)
print('All paired guest timing ended; bootstrap begins',flush=True)
for row in rows:
    plan=row['plan'];samples=row['samples'];row_arms=list(row['binary_paths'])
    values = {arm: [sample['kernel_ns'] for sample in samples
                    if sample['round'] >= 0 and sample['arm'] == arm] for arm in row_arms}
    medians = {arm: statistics.median(value) / plan['iterations'] for arm, value in values.items()}
    comparisons = {backend: {
        'candidate_to_before': medians['candidate-' + backend] / medians['before-' + backend],
        'paired_bootstrap_95_interval': bootstrap(values['candidate-' + backend], values['before-' + backend],
                                                  f"dictionary-probe/{plan['case']}/{plan['profile']}/{backend}")}
        for backend in ('llvm', 'qbe')}
    row.update(medians_ns_per_iteration=medians,comparisons=comparisons)
    print(plan['case'], plan['profile'], comparisons, flush=True)
for arm in ['before','candidate']:
 document=json.loads(Path(manifests[arm]['path']).read_text());holdouts.check_manifest(Path(manifests[arm]['path']),manifests[arm]['sha256'],document)
assert hashes == {key: runner.digest(path) for key, path in binaries.items()}
assert sidecars == {key: runner.digest(Path(str(path) + '.qbe-manifest.json')) for key, path in binaries.items()}
report = {'status': 'complete', 'kind': 'exploratory-paired-dictionary-probe-screen',
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
                     'Control uses source-bound ReleaseFast host, candidate Debug host; both use ordinary ReleaseFast guests with LLVM O3/full LTO. The only production delta is C found-hit publication; frontend IL is verified byte-identical.',
                     'Only fresh calibrated iteration/seed plans are reused; every paired sample is fresh.',
                     'Bootstrap intervals are uncorrected for selection and multiple comparisons.',
                     'Cgroup counters cover the whole group; frequency snapshots do not isolate guest throttling.']}
with args.output.open('x') as target:target.write(json.dumps(report, indent=2) + '\n')
