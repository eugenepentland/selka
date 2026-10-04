#!/usr/bin/env python3
"""Independently replay the saved integrated/index comparison, without timing."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import random
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
from compare_candidate import bootstrap
from registry import checksum, inventory

CASES = ('list_append', 'list_filter', 'sort_int', 'mutate_nested',
         'dict_lookup', 'dict_lookup_str', 'dict_update_str', 'integer_math',
         'float_math', 'call_direct', 'record_reads', 'tagged_stack',
         'mutate_unique', 'mutate_shared')
ARMS = ('before-llvm', 'before-qbe', 'after-llvm', 'after-qbe')
REVISIONS = {'before': '14ffa2c0f385a11e5216bbdec5bdff429f9f981b',
             'after': '1a3980631e79bc65f048acd063d7250800f01901'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    raw, output = map(Path, sys.argv[1:])
    doc = json.loads(raw.read_text())
    assert doc['status'] == 'complete'
    assert (doc['rounds'], doc['warmups'], doc['cpu']) == (5, 1, 2)
    for side, manifest in doc['manifests'].items():
        assert sha(manifest['path']) == manifest['sha256']
        actual = json.loads(Path(manifest['path']).read_text())
        assert actual['identity'] == manifest['identity']
        assert actual['identity']['source_revision'] == REVISIONS[side]
    for key, path in doc['binary_paths'].items():
        assert sha(path) == doc['binary_hashes'][key]
    for path, expected in doc['backend_manifest_sha256'].items():
        assert sha(path) == expected
    for path, expected in doc['helper_sha256'].items():
        assert sha(path) == expected
    assert sha(doc['six_arm_screen']) == doc['six_arm_screen_sha256']
    screen = json.loads(Path(doc['six_arm_screen']).read_text())
    plans = {(p['case'], p['profile']): p for p in screen['plans']}
    rows, seen, total = [], set(), 0
    for row in doc['rows']:
        plan = row['plan']
        key = plan['case'], plan['profile']
        assert key not in seen and plan == plans[key]
        seen.add(key)
        assert plan['group'] == inventory()[key[0]]['group']
        expected = checksum(*[plan[k] for k in ('case', 'size', 'iterations', 'seed')])
        assert expected == plan['expected']
        samples = {(s['round'], s['arm']): s for s in row['samples']}
        assert len(samples) == len(row['samples']) == 24
        assert set(samples) == {(r, a) for r in range(-1, 5) for a in ARMS}
        for rnd in range(-1, 5):
            order = list(ARMS)
            random.Random(f'{key[0]}/{key[1]}/{rnd}').shuffle(order)
            assert [s['arm'] for s in row['samples'] if s['round'] == rnd] == order
        for sample in samples.values():
            assert sample['checksum'] == expected and sample['exit_status'] == 0
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            total += 1
        values = {a: [samples[r, a]['kernel_ns'] / plan['iterations'] for r in range(5)] for a in ARMS}
        medians = {a: statistics.median(v) for a, v in values.items()}
        assert medians == row['medians_ns_per_op']
        comparisons = {}
        for backend in ('llvm', 'qbe'):
            ratio = medians['after-' + backend] / medians['before-' + backend]
            ci = bootstrap(values['after-' + backend], values['before-' + backend],
                           '/'.join(key) + '/' + backend)
            assert ratio == row['after_before_ratios'][backend]
            assert ci == row['paired_bootstrap_95'][backend]
            comparisons[backend] = dict(after_before=ratio, paired_95=ci)
        rows.append(dict(case=key[0], profile=key[1], ns_per_iteration=medians,
                         comparisons=comparisons))
    assert seen == {(c, p) for c in CASES for p in ('small', 'large')}
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  session_id=doc['session_id'], guest_finished_utc=doc['guest_finished_utc'],
                  outcomes=total, rows=rows, raw_sha256=sha(raw),
                  script_sha256=sha(__file__), screen_sha256=sha(doc['six_arm_screen']),
                  limitations=['Saved parsed outcomes, not new guest executions.',
                               'Five-round screen; no target confirmation or simultaneous interval guarantee.',
                               'Before compiler host is ReleaseFast and after host Debug; guests use the same ordinary optimized policy.',
                               'Timing records parsed checksum/status/durations and order, not full stdout/stderr.'])
    with output.open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print(f'PASS {total} outcomes, 28 exact plans, live bindings, medians and paired intervals')


if __name__ == '__main__':
    main()
