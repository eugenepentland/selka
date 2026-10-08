#!/usr/bin/env python3
"""Replay a saved dictionary publication comparison without running guests."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
from compare_candidate import bootstrap
from registry import checksum, inventory

CASES = ('dict_lookup', 'dict_lookup_str', 'dict_update', 'dict_update_str',
         'set_dedup', 'mutate_nested', 'string_search')
ARMS = ('before-llvm', 'before-qbe', 'candidate-llvm', 'candidate-qbe')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    raw, output = map(Path, sys.argv[1:])
    doc = json.loads(raw.read_text())
    assert doc['status'] == 'complete' and doc['cpu'] == 2
    assert (doc['rounds'], doc['warmups']) in ((5, 1), (15, 3))
    assert doc['manifests']['before']['source_revision'] == '14ffa2c0f385a11e5216bbdec5bdff429f9f981b'
    assert doc['manifests']['candidate']['source_revision'] == '64fb7e62732db9cea46414248fd59ba362e31b56'
    for item in doc['manifests'].values():
        assert sha(item['path']) == item['sha256']
    for arm, binary in doc['binaries'].items():
        assert sha(binary) == doc['binary_hashes_before_after'][arm]
        assert sha(binary + '.qbe-manifest.json') == doc['binary_manifest_hashes_before_after'][arm]
    assert sha(doc['six_arm_screen']['path']) == doc['six_arm_screen']['sha256']
    screen = json.loads(Path(doc['six_arm_screen']['path']).read_text())
    screen_plans = {(p['case'], p['profile']): p for p in screen['plans']}
    seen, results, total = set(), [], 0
    for row in doc['rows']:
        plan = row['plan']
        key = plan['case'], plan['profile']
        assert key not in seen and plan == screen_plans[key]
        seen.add(key)
        assert plan['group'] == inventory()[plan['case']]['group']
        expected = checksum(*[plan[k] for k in ('case', 'size', 'iterations', 'seed')])
        assert expected == plan['expected']
        samples = {(s['round'], s['arm']): s for s in row['samples']}
        assert len(samples) == len(row['samples'])
        assert set(samples) == {(r, arm) for r in range(-doc['warmups'], doc['rounds']) for arm in ARMS}
        for (_, arm), sample in samples.items():
            assert sample['exit_status'] == 0 and sample['checksum'] == expected
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            assert set(sample['order']) == set(ARMS) and len(sample['order']) == 4
            label, backend = arm.split('-')
            assert row['binary_paths'][arm] == doc['binaries'][label + '-' + plan['group'] + '-' + backend]
            total += 1
        values = {arm: [samples[r, arm]['kernel_ns'] for r in range(doc['rounds'])] for arm in ARMS}
        medians = {arm: statistics.median(items) / plan['iterations'] for arm, items in values.items()}
        assert medians == row['medians_ns_per_iteration']
        comparisons = {}
        for backend in ('llvm', 'qbe'):
            ratio = medians['candidate-' + backend] / medians['before-' + backend]
            ci = bootstrap(values['candidate-' + backend], values['before-' + backend],
                           f"dictionary-probe/{plan['case']}/{plan['profile']}/{backend}")
            assert ratio == row['comparisons'][backend]['candidate_to_before']
            assert ci == row['comparisons'][backend]['paired_bootstrap_95_interval']
            comparisons[backend] = dict(ratio=ratio, paired_95=ci)
        results.append(dict(case=key[0], profile=key[1], comparisons=comparisons))
    assert seen == {(case, profile) for case in CASES for profile in ('small', 'large')}
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  session=doc['measurement_session_id'], outcomes=total, rows=results,
                  raw_path=str(raw.resolve()), raw_sha256=sha(raw), script_sha256=sha(__file__),
                  bootstrap_helper_sha256=sha(ROOT / 'benchmarks/runtime/compare_candidate.py'),
                  limitations=['Saved parsed timing outcomes; no new guest executions.',
                               'Intervals recomputed with the established helper; no simultaneous coverage claim.',
                               'Exploratory comparison; no goal confirmation.'])
    with output.open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print(f'PASS {total} paired outcomes, exact plans/artifacts, independent oracles, medians and intervals')


if __name__ == '__main__':
    main()
