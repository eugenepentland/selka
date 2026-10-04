#!/usr/bin/env python3
"""Independently replay complete alignment timing streams and paired intervals."""
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
from registry import checksum


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    paths = list(map(Path, sys.argv[1:-1]))
    assert len(paths) == 2
    rows, sessions, total, seen, policies = [], [], 0, set(), set()
    for path in paths:
        doc = json.loads(path.read_text())
        assert doc['status'] == 'complete' and doc['cpu'] == 2
        assert (doc['rounds'], doc['warmups']) in ((5, 1), (15, 3))
        policies.add((doc['rounds'], doc['warmups']))
        assert sha(doc['screen']) == doc['screen_sha256']
        screen = json.loads(Path(doc['screen']).read_text())
        plans = {(p['case'], p['profile']): p for p in screen['plans']}
        manifests = {}
        for side, binding in doc['bindings']['arms'].items():
            assert sha(binding['manifest']) == binding['manifest_sha256']
            manifests[side] = json.loads(Path(binding['manifest']).read_text())
            assert manifests[side]['identity']['source_revision'] == binding['source_revision']
        assert manifests['before']['identity']['source_revision'] == '1a3980631e79bc65f048acd063d7250800f01901'
        assert manifests['after']['identity']['source_revision'] == '5818cee8e679c1f30fd5966963210511fcf69919'
        for key, expected in doc['binary_hashes'].items():
            group, rest = key.split('/')
            side, backend = rest.split('-')
            binary = manifests[side]['identity']['binary_paths'][group + '/my-' + backend]
            assert sha(binary) == expected
        for row in doc['rows']:
            plan = row['plan']
            key = plan['case'], plan['profile']
            assert key not in seen and plan == plans[key]
            seen.add(key)
            expected = checksum(*[plan[k] for k in ('case', 'size', 'iterations', 'seed')])
            assert plan['expected'] == expected
            arms = [side + '-' + backend for side in doc['bindings']['arms'] for backend in ('llvm', 'qbe')]
            samples = {(s['round'], s['arm']): s for s in row['samples']}
            assert len(samples) == len(row['samples'])
            assert set(samples) == {(r, a) for r in range(-doc['warmups'], doc['rounds']) for a in arms}
            for rnd in range(-doc['warmups'], doc['rounds']):
                order = arms.copy()
                random.Random('/'.join(key) + '/' + str(rnd)).shuffle(order)
                assert [s['arm'] for s in row['samples'] if s['round'] == rnd] == order
            for (_, arm), sample in samples.items():
                actual, clock = map(int, sample['stdout'].split())
                assert sample['status'] == sample['exit_status'] == 0 and sample['stderr'] == ''
                assert actual == sample['checksum'] == expected and clock == sample['kernel_ns'] > 0
                side, backend = arm.split('-')
                binary = manifests[side]['identity']['binary_paths'][plan['group'] + '/my-' + backend]
                assert sample['command'] == ['taskset', '-c', '2', binary, *map(str, [plan[k] for k in ('case', 'size', 'iterations', 'seed')])]
                total += 1
            values = {a: [samples[r, a]['kernel_ns'] / plan['iterations'] for r in range(doc['rounds'])] for a in arms}
            medians = {a: statistics.median(v) for a, v in values.items()}
            assert medians == row['medians_ns_per_op']
            comparisons = {}
            for backend in ('llvm', 'qbe'):
                ratio = medians['after-' + backend] / medians['before-' + backend]
                assert ratio == row['after_before_ratios'][backend]
                ci = bootstrap(values['after-' + backend], values['before-' + backend], '/'.join(key) + '/' + backend)
                comparisons[backend] = dict(after_before=ratio, paired_95=ci)
            rows.append(dict(case=key[0], profile=key[1], comparisons=comparisons))
        sessions.append(dict(session_id=doc['session_id'], guest_finished_utc=doc['guest_finished_utc'], raw_sha256=sha(path)))
    assert len(policies) == 1
    assert (len(seen), total) == ((40, 960) if policies == {(5, 1)} else (7, 504))
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(), sessions=sessions,
                  rows=rows, outcomes=total, script_sha256=sha(__file__),
                  limitations=['Saved complete process streams and live artifacts; no new execution.',
                               'Paired intervals use the established bootstrap helper; no simultaneous guarantee or goal confirmation.'])
    with Path(sys.argv[-1]).open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print(f'PASS {total} full outcomes, {len(seen)} plans, orders, artifacts, medians and paired intervals')


if __name__ == '__main__':
    main()
