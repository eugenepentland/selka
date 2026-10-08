#!/usr/bin/env python3
"""Exploratory integrated/index comparison using identical six-arm calibrated plans."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import statistics
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
from compare_candidate import bootstrap
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum, inventory

CASES = ('list_append', 'list_filter', 'sort_int', 'mutate_nested',
         'dict_lookup', 'dict_lookup_str', 'dict_update_str',
         'integer_math', 'float_math', 'call_direct',
         'record_reads', 'tagged_stack', 'mutate_unique', 'mutate_shared')
REVISIONS = {'before': '14ffa2c0f385a11e5216bbdec5bdff429f9f981b',
             'after': '1a3980631e79bc65f048acd063d7250800f01901'}
ARMS = ('before-llvm', 'before-qbe', 'after-llvm', 'after-qbe')
SCHEMA = 'mylang-goal110-integrated-paired-screen-v1'


def stamp():
    return datetime.now(timezone.utc).isoformat()


def save(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def preflight(args):
    manifests, paths, hashes, binaries, sidecars = {}, {}, {}, {}, {}
    for label, revision in REVISIONS.items():
        path = getattr(args, label + '_manifest').resolve()
        expected = getattr(args, label + '_manifest_sha256')
        assert runner.digest(path) == expected, label + ' manifest hash'
        document = json.loads(path.read_text())
        holdouts.check_manifest(path, expected, document)
        assert document['identity']['source_revision'] == revision
        assert document['identity']['compiler_build_receipt']['receipt']['compiler_optimize'] == {
            'before': 'ReleaseFast', 'after': 'Debug'}[label]
        manifests[label], paths[label], hashes[label] = document, path, expected
        for group in {inventory()[case]['group'] for case in CASES}:
            for backend in ('llvm', 'qbe'):
                name = group + '/my-' + backend
                binary = Path(document['identity']['binary_paths'][name])
                assert runner.digest(binary) == document['binary_hashes'][name]
                binaries[label + '/' + name] = binary
                sidecar = Path(str(binary) + '.qbe-manifest.json')
                policy = json.loads(sidecar.read_text())
                assert policy['backend'] == backend
                if backend == 'llvm':
                    assert str(policy['optimization']) == '3' and policy['lto'] and not policy['thin_lto']
                sidecars[str(sidecar)] = runner.digest(sidecar)
    return manifests, paths, hashes, binaries, sidecars


def replay(report):
    assert report['schema'] == SCHEMA and report['status'] == 'complete'
    assert (report['rounds'], report['warmups'], report['cpu']) == (5, 1, 2)
    seen = set()
    for row in report['rows']:
        plan = row['plan']; key = plan['case'], plan['profile']
        assert key not in seen and key[0] in CASES and key[1] in ('small', 'large')
        seen.add(key)
        assert plan['group'] == inventory()[key[0]]['group']
        assert plan['expected'] == checksum(plan['case'], plan['size'], plan['iterations'], plan['seed'])
        samples = {}
        for sample in row['samples']:
            pair = sample['round'], sample['arm']
            assert pair not in samples and pair[0] in range(-1, 5) and pair[1] in ARMS
            assert sample['checksum'] == plan['expected'] and sample['exit_status'] == 0
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            samples[pair] = sample['kernel_ns'] / plan['iterations']
        assert set(samples) == {(rnd, arm) for rnd in range(-1, 5) for arm in ARMS}
        medians = {arm: statistics.median(samples[rnd, arm] for rnd in range(5)) for arm in ARMS}
        assert row['medians_ns_per_op'] == medians
        for backend in ('llvm', 'qbe'):
            assert row['after_before_ratios'][backend] == medians['after-' + backend] / medians['before-' + backend]
            assert row['paired_bootstrap_95'][backend] == bootstrap(
                [samples[rnd, 'after-' + backend] for rnd in range(5)],
                [samples[rnd, 'before-' + backend] for rnd in range(5)], '/'.join(key) + '/' + backend)
    assert seen == {(case, size) for case in CASES for size in ('small', 'large')}
    return len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for label in REVISIONS:
        parser.add_argument('--' + label + '-manifest', type=Path)
        parser.add_argument('--' + label + '-manifest-sha256')
    parser.add_argument('--screen', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify', type=Path)
    parser.add_argument('--preflight-only', action='store_true')
    args = parser.parse_args()
    if args.verify:
        print('PASS paired replay: ' + str(replay(json.loads(args.verify.read_text()))) + ' plans')
        return
    assert all(getattr(args, label + '_manifest') and getattr(args, label + '_manifest_sha256') for label in REVISIONS)
    manifests, paths, hashes, binaries, sidecars = preflight(args)
    if args.preflight_only:
        print('PASS pinned source/host/backend policy and twelve MyLang guest artifacts; no guest execution')
        return
    assert args.screen and args.output and not args.output.exists()
    screen_hash = runner.digest(args.screen)
    screen = json.loads(args.screen.read_text())
    assert screen['status'] == 'subset' and screen['rounds'] == 5 and screen['warmup_rounds'] == 1
    assert screen['coverage'] == list(CASES)
    assert screen['identity'] == manifests['after']['identity']
    assert screen['binary_hashes'] == manifests['after']['binary_hashes']
    helpers = {str(path): runner.digest(path) for path in (Path(__file__).resolve(),
               ROOT / 'benchmarks/runtime/runner.py', ROOT / 'benchmarks/runtime/compare_candidate.py',
               ROOT / 'benchmarks/runtime/expanded/registry.py', ROOT / 'benchmarks/runtime/diagnostics/holdouts.py')}
    binary_hashes = {key: runner.digest(path) for key, path in binaries.items()}
    report = dict(schema=SCHEMA, status='in_progress', session_id=str(uuid.uuid4()), started_utc=stamp(),
                  six_arm_screen=str(args.screen.resolve()), six_arm_screen_sha256=screen_hash,
                  manifests={label: dict(path=str(paths[label]), sha256=hashes[label], identity=value['identity'])
                             for label, value in manifests.items()},
                  binary_paths={key: str(path) for key, path in binaries.items()}, binary_hashes=binary_hashes,
                  backend_manifest_sha256=sidecars, helper_sha256=helpers,
                  rounds=5, warmups=1, cpu=2, rows=[], timing_lock=str(runner.TIMING_LOCK),
                  limitations=['Exploratory screen only; no normal acceptance or independent confirmation.',
                               'Index control host ReleaseFast; integrated host Debug; guests ordinary RF LLVM-O3/fullLTO and default QBE.',
                               'Exact same plans/iterations/seed for both sources; four arms shuffled within each paired round.',
                               'Individual paired intervals lack multiple-comparison correction.'])
    save(args.output, report)
    cpu_before = runner.cpu_snapshot()
    for plan in screen['plans']:
        assert plan['case'] in CASES and plan['group'] == inventory()[plan['case']]['group']
        samples = []
        for rnd in range(-1, 5):
            order = list(ARMS)
            random.Random(f"{plan['case']}/{plan['profile']}/{rnd}").shuffle(order)
            for arm in order:
                label, backend = arm.split('-')
                binary = binaries[label + '/' + plan['group'] + '/my-' + backend]
                samples.append(dict(round=rnd, arm=arm, **runner.invoke(binary, plan['case'], plan['size'],
                               plan['iterations'], plan['seed'], 2, plan['expected'])))
        medians = {arm: statistics.median(sample['kernel_ns'] / plan['iterations'] for sample in samples
                                         if sample['round'] >= 0 and sample['arm'] == arm) for arm in ARMS}
        ratios = {backend: medians['after-' + backend] / medians['before-' + backend] for backend in ('llvm', 'qbe')}
        report['rows'].append(dict(plan=plan, samples=samples, medians_ns_per_op=medians, after_before_ratios=ratios))
        save(args.output, report)
        print(plan['case'], plan['profile'], ratios, flush=True)
    report['guest_finished_utc'] = stamp()
    print('Guest timing complete ' + report['guest_finished_utc'], flush=True)
    for row in report['rows']:
        plan = row['plan']
        values = {arm: [sample['kernel_ns'] / plan['iterations'] for sample in row['samples']
                       if sample['round'] >= 0 and sample['arm'] == arm] for arm in ARMS}
        row['paired_bootstrap_95'] = {backend: bootstrap(values['after-' + backend], values['before-' + backend],
                                                    plan['case'] + '/' + plan['profile'] + '/' + backend)
                                    for backend in ('llvm', 'qbe')}
    preflight(args)
    assert sidecars == {path: runner.digest(path) for path in sidecars}
    assert helpers == {path: runner.digest(path) for path in helpers}
    assert binary_hashes == {key: runner.digest(path) for key, path in binaries.items()}
    assert screen_hash == runner.digest(args.screen)
    report.update(status='complete', finished_utc=stamp(),
                  environment=runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()))
    replay(report)
    save(args.output, report)
    print('PASS paired integrated screen: 560 measured samples,112 warmups', flush=True)


if __name__ == '__main__':
    main()
