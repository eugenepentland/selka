#!/usr/bin/env python3
"""Exploratory five-round Debug-host before/after screen on frozen plans."""
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
from compare_candidate import bootstrap
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts
from registry import checksum

REVISIONS = {'before': '5a60ef1039aca32657ef5877a464eb8a81d6c115',
             'after': '8043c4d9e0ad907c8a1b9e8416a1e58815eef0df'}
CASES = ('sort_records', 'sort_int', 'mutate_nested', 'list_append')
ARMS = ('before-llvm', 'before-qbe', 'after-llvm', 'after-qbe')


def stamp():
    return datetime.now(timezone.utc).isoformat()


def replay(report):
    assert report['schema'] == 'mylang-goal110-sort-paired-screen-v1' and report['status'] == 'complete'
    assert report['rounds'] == 5 and report['warmups'] == 1 and report['cpu'] == 2
    seen = set()
    for row in report['rows']:
        plan = row['plan']; key = plan['case'], plan['profile']
        assert key not in seen and key[0] in CASES and key[1] in ('small', 'large')
        seen.add(key)
        samples = {}
        for sample in row['samples']:
            pair = sample['round'], sample['arm']
            assert pair not in samples and pair[0] in range(-1, 5) and pair[1] in ARMS
            assert sample['checksum'] == checksum(plan['case'], plan['size'], plan['iterations'], plan['seed']) == plan['expected']
            assert sample['exit_status'] == 0 and sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            samples[pair] = sample['kernel_ns'] / plan['iterations']
        assert set(samples) == {(rnd, arm) for rnd in range(-1, 5) for arm in ARMS}
        medians = {arm: statistics.median(samples[rnd, arm] for rnd in range(5)) for arm in ARMS}
        assert row['medians_ns_per_op'] == medians
        for backend in ('llvm', 'qbe'):
            ratio = medians['after-' + backend] / medians['before-' + backend]
            assert row['after_before_ratios'][backend] == ratio
            assert row['paired_bootstrap_95'][backend] == bootstrap(
                [samples[rnd, 'after-' + backend] for rnd in range(5)],
                [samples[rnd, 'before-' + backend] for rnd in range(5)], '/'.join(key) + '/' + backend)
    assert seen == {(case, profile) for case in CASES for profile in ('small', 'large')}
    return len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screen', type=Path)
    parser.add_argument('--before-manifest', type=Path)
    parser.add_argument('--after-manifest', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        print('PASS paired screen replay: ' + str(replay(json.loads(args.verify.read_text()))) + ' plans')
        return
    if any(getattr(args, name) is None for name in ('screen', 'before_manifest', 'after_manifest', 'output')):
        parser.error('screen, both manifests and output required')
    screen_hash = runner.digest(args.screen)
    screen = json.loads(args.screen.read_text())
    assert screen['status'] == 'subset' and screen['rounds'] == 5 and screen['warmup_rounds'] == 1
    assert screen['coverage'] == list(CASES)
    manifests = {label: json.loads(getattr(args, label + '_manifest').read_text()) for label in REVISIONS}
    paths = {label: getattr(args, label + '_manifest').resolve() for label in REVISIONS}
    hashes = {label: runner.digest(path) for label, path in paths.items()}
    helper_hashes = {str(path): runner.digest(path) for path in (Path(__file__), ROOT / 'benchmarks/runtime/runner.py',
                     ROOT / 'benchmarks/runtime/compare_candidate.py', ROOT / 'benchmarks/runtime/diagnostics/holdouts.py')}
    binaries = {}; backend_manifests = {}
    for label, manifest in manifests.items():
        holdouts.check_manifest(paths[label], hashes[label], manifest)
        assert manifest['identity']['source_revision'] == REVISIONS[label]
        assert manifest['identity']['compiler_build_receipt']['receipt']['compiler_optimize'] == 'Debug'
        for backend in ('llvm', 'qbe'):
            name = label + '-' + backend
            binaries[name] = Path(manifest['identity']['binary_paths']['collections/my-' + backend])
            path = Path(str(binaries[name]) + '.qbe-manifest.json')
            backend_manifest = json.loads(path.read_text())
            assert backend_manifest['backend'] == backend
            if backend == 'llvm': assert str(backend_manifest['optimization']) == '3' and backend_manifest['lto']
            backend_manifests[str(path)] = runner.digest(path)
    assert manifests['after']['identity'] == screen['identity'] and manifests['after']['binary_hashes'] == screen['binary_hashes']
    binary_hashes = {name: runner.digest(path) for name, path in binaries.items()}
    report = {'schema': 'mylang-goal110-sort-paired-screen-v1', 'status': 'in_progress', 'started_utc': stamp(),
              'six_arm_screen': str(args.screen.resolve()), 'six_arm_screen_sha256': screen_hash,
              'manifests': {label: {'path': str(paths[label]), 'sha256': hashes[label], 'identity': doc['identity']} for label, doc in manifests.items()},
              'binaries': {name: str(path) for name, path in binaries.items()}, 'binary_hashes_before_after': binary_hashes,
              'backend_manifest_sha256': backend_manifests, 'helper_sha256': helper_hashes,
              'rounds': 5, 'warmups': 1, 'cpu': 2, 'rows': [],
              'limitations': ['Exploratory five-round screen: not a normal acceptance or independent confirmation session.',
                              'Both hosts are Debug; all guests retain ordinary ReleaseFast backend policy.',
                              'Paired intervals resample identical round indexes, without multiple-comparison correction.']}
    cpu_before = runner.cpu_snapshot()
    for plan in screen['plans']:
        samples = []
        for rnd in range(-1, 5):
            order = list(ARMS)
            random.Random(f"{plan['case']}/{plan['profile']}/{rnd}").shuffle(order)
            for arm in order:
                samples.append({'round': rnd, 'arm': arm, **runner.invoke(binaries[arm], plan['case'], plan['size'], plan['iterations'], plan['seed'], 2, plan['expected'])})
        values = {arm: [row['kernel_ns'] / plan['iterations'] for row in samples if row['round'] >= 0 and row['arm'] == arm] for arm in ARMS}
        medians = {arm: statistics.median(data) for arm, data in values.items()}
        ratios = {backend: medians['after-' + backend] / medians['before-' + backend] for backend in ('llvm', 'qbe')}
        report['rows'].append({'plan': plan, 'samples': samples, 'medians_ns_per_op': medians, 'after_before_ratios': ratios})
        print(plan['case'], plan['profile'], ratios, flush=True)
    # All guest timing ends before bootstrap or independent report replay.
    print('Guest timing complete; computing exploratory paired intervals', flush=True)
    for row in report['rows']:
        plan = row['plan']
        values = {arm: [sample['kernel_ns'] / plan['iterations'] for sample in row['samples'] if sample['round'] >= 0 and sample['arm'] == arm] for arm in ARMS}
        row['paired_bootstrap_95'] = {backend: bootstrap(values['after-' + backend], values['before-' + backend], plan['case'] + '/' + plan['profile'] + '/' + backend) for backend in ('llvm', 'qbe')}
    for label, manifest in manifests.items(): holdouts.check_manifest(paths[label], hashes[label], manifest)
    assert screen_hash == runner.digest(args.screen) and binary_hashes == {name: runner.digest(path) for name, path in binaries.items()}
    assert backend_manifests == {path: runner.digest(path) for path in backend_manifests}
    assert helper_hashes == {path: runner.digest(path) for path in helper_hashes}
    report.update(status='complete', finished_utc=stamp(), environment=runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()))
    replay(report)
    with args.output.open('x') as target: target.write(json.dumps(report, indent=2) + '\n')
    print('PASS paired Debug-host sort screen: 160 measured samples, 32 warmups')


if __name__ == '__main__':
    main()
