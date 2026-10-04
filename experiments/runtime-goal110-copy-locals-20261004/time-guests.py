"""Exploratory paired compute guests; pinned historical plans, fresh samples.

This does not measure current references and cannot establish 1.10 acceptance.
Run only in the timing window granted by the parent agent.
"""
import argparse
from datetime import datetime, timezone
import gzip
import importlib.util
import json
import os
from pathlib import Path
import random
import statistics
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
from compare_candidate import bootstrap

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cases', nargs='+', required=True)
parser.add_argument('--rounds', type=int, default=5)
parser.add_argument('--warmups', type=int, default=1)
parser.add_argument('--cpu', type=int, default=2)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert args.rounds > 0 and args.warmups >= 0 and args.cpu in os.sched_getaffinity(0)
archive = ROOT / 'benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz'
with gzip.open(archive, 'rt') as source:
    old = json.load(source)
assert old['status'] == 'complete'
plans = [p for case in args.cases for p in old['plans'] if p['case'] == case]
assert len(plans) == 2 * len(args.cases) and len(set(args.cases)) == len(args.cases)
spec = importlib.util.spec_from_file_location('compute_oracle', ROOT / 'benchmarks/runtime/expanded/compute/oracle.py')
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
for plan in plans:
    assert plan['group'] == 'compute'
    assert plan['expected'] == oracle.checksum(plan['case'], plan['size'], plan['iterations'], plan['seed'])
sizes_path = EVIDENCE / 'paired-artifacts.json'
sizes = json.loads(sizes_path.read_text())
binaries = {r['arm'] + '-' + r['backend']: Path(r['binary']) for r in sizes['records']}
hashes = {key: runner.digest(path) for key, path in binaries.items()}
for record in sizes['records']:
    assert hashes[record['arm'] + '-' + record['backend']] == record['binary_sha256']
manifest_hashes = {}
for arm, binary in binaries.items():
    path = Path(str(binary) + '.qbe-manifest.json')
    manifest = json.loads(path.read_text())
    assert manifest['backend'] == arm.split('-')[1]
    assert manifest['backend'] != 'llvm' or (str(manifest['optimization']) == '3' and manifest['lto'])
    manifest_hashes[arm] = runner.digest(path)


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
        random.Random(f"loop-copy/{plan['case']}/{plan['profile']}/{round_index}").shuffle(arms)
        for arm in arms:
            host_before = host_counters()
            sample = {'round': round_index, 'arm': arm,
                      **runner.invoke(binaries[arm], plan['case'], plan['size'],
                                      plan['iterations'], plan['seed'], args.cpu, plan['expected']),
                      'host_before': host_before, 'host_after': host_counters()}
            samples.append(sample)
    values = {arm: [sample['kernel_ns'] for sample in samples
                    if sample['round'] >= 0 and sample['arm'] == arm] for arm in binaries}
    medians = {arm: statistics.median(v) / plan['iterations'] for arm, v in values.items()}
    comparisons = {backend: {
        'candidate_to_before': medians['candidate-' + backend] / medians['before-' + backend],
        'paired_bootstrap_95_interval': bootstrap(values['candidate-' + backend], values['before-' + backend],
                                                  f"loop-copy/{plan['case']}/{plan['profile']}/{backend}")}
        for backend in ('llvm', 'qbe')}
    rows.append({'plan': plan, 'samples': samples, 'medians_ns_per_iteration': medians,
                 'comparisons': comparisons})
    print(plan['case'], plan['profile'], comparisons, flush=True)

assert hashes == {key: runner.digest(path) for key, path in binaries.items()}
assert manifest_hashes == {key: runner.digest(Path(str(path) + '.qbe-manifest.json'))
                           for key, path in binaries.items()}
report = {'status': 'complete', 'kind': 'exploratory-paired-compute-before-after-screen',
          'measurement_session_id': str(uuid.uuid4()), 'source_revision': 'd14e26f4473d6c50f56751736ed8ef325adcaecd',
          'before_source_revision': '730a86e6', 'before_host_mode': 'Debug',
          'candidate_host_mode': 'Debug', 'guest_mode': 'ReleaseFast', 'started_utc': started,
          'finished_utc': datetime.now(timezone.utc).isoformat(),
          'binary_hashes_before_after': hashes, 'binary_manifest_hashes_before_after': manifest_hashes,
          'binaries': {key: str(path) for key, path in binaries.items()},
          'reused_calibration_plans': str(archive), 'calibration_archive_sha256': runner.digest(archive),
          'paired_artifacts_receipt_sha256': runner.digest(sizes_path),
          'compiler_receipt_sha256': runner.digest(EVIDENCE / 'compiler-build-receipt.json'),
          'source_sha256': runner.digest(ROOT / 'benchmarks/runtime/expanded/compute/main.my'),
          'oracle_sha256': runner.digest(ROOT / 'benchmarks/runtime/expanded/compute/oracle.py'),
          'runner_sha256': runner.digest(ROOT / 'benchmarks/runtime/runner.py'),
          'script_sha256': runner.digest(Path(__file__)),
          'environment': runner.cpu_environment(args.cpu, cpu_before, runner.cpu_snapshot()),
          'cpu': args.cpu, 'rounds': args.rounds, 'warmups': args.warmups, 'rows': rows,
          'limits': ['Historical samples are never paired; only exact historical iteration/seed plans are reused.',
                     'Fresh paired rounds compare only pinned before/candidate MyLang binaries; current fastest references were not measured.',
                     'Bootstrap intervals are exploratory and uncorrected for selection, multiple comparisons or tuning; an independent session is required.',
                     'Cgroup counters cover all processes in a group and frequency reads are snapshots; neither isolates guest throttling or achieved frequency.']}
args.output.write_text(json.dumps(report, indent=2) + '\n')
