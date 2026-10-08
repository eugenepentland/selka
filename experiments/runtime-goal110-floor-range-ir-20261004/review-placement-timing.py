#!/usr/bin/env python3
"""Replay the saved three-arm placement diagnostic without running guests."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
from compare_candidate import bootstrap
from registry import checksum


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    raw, output = map(Path, sys.argv[1:])
    doc = json.loads(raw.read_text())
    assert doc['status'] == 'complete' and (doc['rounds'], doc['warmups'], doc['cpu']) == (15, 3, 2)
    assert sha(doc['screen']) == doc['screen_sha256']
    screen = json.loads(Path(doc['screen']).read_text())
    for arm, binding in doc['binaries'].items():
        assert sha(binding['path']) == binding['sha256'] == doc['binary_hashes'][arm]
    arms = {'g4', 'annotation', 'fill32'}
    assert set(doc['binaries']) == arms
    rows, seen, count = [], set(), 0
    for row in doc['rows']:
        plan = row['plan']
        assert plan in screen['plans']
        key = plan['case'], plan['profile']
        assert key not in seen
        seen.add(key)
        expected = checksum(*[plan[k] for k in ('case', 'size', 'iterations', 'seed')])
        assert expected == plan['expected']
        samples = {(r['round'], r['arm']): r for r in row['samples']}
        assert len(samples) == len(row['samples']) == 54
        assert set(samples) == {(round, arm) for round in range(-3, 15) for arm in arms}
        for (_, arm), sample in samples.items():
            assert sample['status'] == sample['exit_status'] == 0 and sample['stderr'] == ''
            match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', sample['stdout'])
            assert match and int(match[1]) == sample['checksum'] == expected
            assert int(match[2]) == sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            assert sample['command'] == ['taskset', '-c', '2', doc['binaries'][arm]['path'], plan['case'],
                                         str(plan['size']), str(plan['iterations']), str(plan['seed'])]
            count += 1
        values = {arm: [samples[index, arm]['kernel_ns'] for index in range(15)] for arm in arms}
        medians = {arm: statistics.median(v) / plan['iterations'] for arm, v in values.items()}
        assert medians == row['medians_ns_per_op']
        ratios = {}
        for name in ('annotation/g4', 'fill32/annotation', 'fill32/g4'):
            left, right = name.split('/')
            ratio = medians[left] / medians[right]
            assert ratio == row['ratios'][name]
            ratios[name] = dict(ratio=ratio, paired_95=bootstrap(values[left], values[right],
                                 f'placement-review/{key[0]}/{key[1]}/{name}'))
        rows.append(dict(case=key[0], profile=key[1], ratios=ratios))
    assert seen == {('string_equal', 'small'), ('string_search', 'large')}
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  session=doc['session_id'], outcomes=count, rows=rows, raw_sha256=sha(raw),
                  script_sha256=sha(__file__), bootstrap_helper_sha256=sha(ROOT / 'benchmarks/runtime/compare_candidate.py'),
                  limitations=['Saved full timing streams; no new executions or goal confirmation.',
                               'Intervals use 2000 paired bootstrap draws, independently seeded; agent analysis uses 20000.',
                               'Placement of later symbols also changes, so this does not isolate the caller address.'])
    with output.open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS 108 full outcomes, artifact identities, frozen plans, independent oracles and ratios')


if __name__ == '__main__':
    main()
