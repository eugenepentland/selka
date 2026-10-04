#!/usr/bin/env python3
"""Replay official index-reuse correctness and two saved paired sessions."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-index-forward-rf-20261004'
CACHE = TREE / '.mylang-cache/goal110-index-forward-rf'
SOURCE = '14ffa2c0f385a11e5216bbdec5bdff429f9f981b'
spec = importlib.util.spec_from_file_location('native_review', Path(__file__).with_name('review-native.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum


def read(name):
    return json.loads((CACHE / name).read_text())


def native_checks():
    counts = dict(success=0, failure=0, memory_refusal=0, gc=0, instrumentation=0)
    active = read('native-checks/active/active-receipt.json')
    assert not active['diagnostic_only']
    for row in active['comparisons'] + active['gc_comparisons']:
        before, after = (native.outcome(row['arms'][arm]) for arm in ('before', 'after'))
        assert before == after
        if row.get('kind') == 'memory_refusal':
            assert before[0:2] == (1, '41\n') and 'error[R_MEMORY_BUDGET]' in before[2]
            counts['memory_refusal'] += 1
            continue
        value, code = native.oracle(row['args'])
        assert row['expected'] == value
        if code:
            assert row['expected_code'] == code
            assert before[0:2] == (1, '41\n')
            assert re.search(r'error\[([^]]+)\]', before[2]).group(1) == code
            assert '\n  in ' in before[2]
        else:
            assert before == (value % 256, f'41\n{value}\n', '')
        if row in active['gc_comparisons']:
            counts['gc'] += 1
        else:
            counts['failure' if code else 'success'] += 1
    counted = read('native-checks/counting/native-receipt.json')
    assert not counted['diagnostic_only']
    for row in counted['comparisons']:
        before, after = (native.outcome(row['arms'][arm]) for arm in ('before', 'after'))
        assert before == after
        assert before[0:2] == (90, '41\n1114\n') and 'MYLANG_RC_' in before[2]
        counts['instrumentation'] += 1
    assert counts == dict(success=106, failure=30, memory_refusal=2, gc=8, instrumentation=4)
    return counts


def recorded_checks(name, identity):
    doc = read(name)
    assert doc['binary_hashes'] == identity['binary_hashes']
    assert doc['manifest_sha256'] == native.digest(CACHE / 'runner/manifest.json')
    seen = set()
    for row in doc['checks']:
        key = tuple(row[k] for k in ('case', 'size', 'iterations', 'seed', 'arm'))
        assert key not in seen
        seen.add(key)
        assert row['checksum'] == checksum(*key[:4]) == row['expected_checksum']
        assert row['exit_status'] == 0 and row['clock_protocol_validated']
    return len(seen)


def paired(name):
    doc = read(name)
    assert doc['status'] == 'complete'
    arms = ('before-llvm', 'before-qbe', 'candidate-llvm', 'candidate-qbe')
    for arm, binary in doc['binaries'].items():
        assert native.digest(binary) == doc['binary_hashes_before_after'][arm]
        assert native.digest(binary + '.qbe-manifest.json') == doc['binary_manifest_hashes_before_after'][arm]
    seen, total, ratios = set(), 0, []
    for row in doc['rows']:
        plan = row['plan']
        key = (plan['case'], plan['size'])
        assert key not in seen
        seen.add(key)
        expected = checksum(*[plan[k] for k in ('case', 'size', 'iterations', 'seed')])
        assert expected == plan['expected']
        samples = {(x['round'], x['arm']): x for x in row['samples']}
        assert len(samples) == len(row['samples'])
        assert set(samples) == {(r, arm) for r in range(-doc['warmups'], doc['rounds']) for arm in arms}
        for sample in samples.values():
            assert sample['checksum'] == expected and sample['exit_status'] == 0
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            total += 1
        medians = {arm: statistics.median(samples[r, arm]['kernel_ns'] / plan['iterations']
                                         for r in range(doc['rounds'])) for arm in arms}
        assert medians == row['medians_ns_per_iteration']
        after_before = {backend: medians['candidate-' + backend] / medians['before-' + backend]
                        for backend in ('llvm', 'qbe')}
        for backend, ratio in after_before.items():
            assert ratio == row['comparisons'][backend]['candidate_to_before']
        ratios.append(dict(case=key[0], size=key[1], after_before=after_before,
                           reported_intervals={k: v['paired_bootstrap_95_interval']
                                               for k, v in row['comparisons'].items()}))
    assert seen == {(case, size) for case, sizes in
                    [('mutate_unique', (64, 1024)), ('mutate_shared', (64, 1024)),
                     ('record_reads', (64, 4096))] for size in sizes}
    return dict(session=doc['measurement_session_id'], outcomes=total, rows=ratios,
                raw_sha256=native.digest(CACHE / name))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    readiness = read('readiness.json')
    assert readiness['source_revision'] == SOURCE
    assert readiness['status'] == 'correctness_and_static_complete'
    for item in readiness['receipt_bindings'].values():
        native.binding(item)
    manifest = read('runner/manifest.json')
    identity = manifest['identity']
    host = read('compiler-receipt.json')
    assert host['source_revision'] == identity['source_revision'] == SOURCE
    assert host['status'] == 'complete' and host['exit_status'] == 0
    assert host['compiler_optimize'] == 'ReleaseFast'
    assert host['sources_before'] == host['sources_after']
    for path, expected in host['sources_after'].items():
        assert native.digest(TREE / path) == expected
    for path, expected in identity['installed_assets'].items():
        assert native.digest(path) == expected
    assert native.digest(host['compiler_path']) == host['compiler_sha256']
    for item in readiness['guest_artifacts']:
        native.binding(item)
        if 'backend_metadata' in item:
            native.binding(item['backend_metadata'])
    results = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                   source_revision=SOURCE, source_bindings=len(host['sources_after']),
                   asset_bindings=len(identity['installed_assets']),
                   guest_bindings=len(readiness['guest_artifacts']), native=native_checks(),
                   qualification=recorded_checks('qualification.json', manifest),
                   holdouts=recorded_checks('holdouts.json', manifest),
                   initial=paired('paired-screen.json'), repeat=paired('paired-repeat.json'),
                   script_sha256=native.digest(__file__),
                   limitations=['Saved outcomes and current identities; no new executions.',
                                'Paired medians and oracles independently recomputed; reported confidence intervals are not independently recomputed.',
                                'Timing outcomes retain parsed checksums/status, not full streams.',
                                'Exploratory adoption evidence; no goal confirmation or whole-repository gate.'])
    assert results['qualification'] == 720 and results['holdouts'] == 516
    assert results['initial']['outcomes'] == 144 and results['repeat']['outcomes'] == 432
    assert results['initial']['session'] != results['repeat']['session']
    with args.output.open('x') as target:
        target.write(json.dumps(results, indent=2) + '\n')
    print('PASS official native/GC/accounting, 1236 qualification/holdouts and 576 paired outcomes')


if __name__ == '__main__':
    main()
