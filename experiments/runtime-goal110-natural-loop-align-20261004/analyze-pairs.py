#!/usr/bin/env python3
"""Replay complete saved paired streams and resample matching round indices."""
import hashlib
import json
from pathlib import Path
import random
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
from compare_candidate import bootstrap


def artifact(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


output = Path(sys.argv[1])
inputs = [Path(value) for value in sys.argv[2:]]
assert not output.exists() and inputs
report = {'status': 'running', 'helper': artifact(__file__),
          'bootstrap_helper': artifact(ROOT / 'benchmarks/runtime/compare_candidate.py'),
          'method': '2000 paired round-index resamples, ratio of medians, seed case/profile/backend',
          'limitations': ['Exploratory Debug hosts with ReleaseFast guests; no normal confirmation.',
                         'Five rounds have coarse intervals. Selection and multiple comparisons are uncorrected.',
                         'Host counters include other cgroup processes; snapshot frequency is not achieved frequency.'],
          'inputs': [], 'rows': [], 'outcomes_replayed': 0}
for path in inputs:
    document = json.loads(path.read_text())
    assert document['status'] == 'complete' and document['cpu'] == 2
    report['inputs'].append(artifact(path))
    screen = json.loads(Path(document['screen']).read_text())
    assert artifact(document['screen'])['sha256'] == document['screen_sha256']
    assert artifact(__file__)['sha256'] == report['helper']['sha256']
    plans = {plan['case'] + '/' + plan['profile']: plan for plan in screen['plans']}
    for row in document['rows']:
        plan = row['plan']; key = plan['case'] + '/' + plan['profile']
        assert plans[key] == plan
        values = {arm: {} for arm in ('before-llvm', 'before-qbe', 'after-llvm', 'after-qbe')}
        by_round = {}
        for sample in row['samples']:
            arm = sample['arm']; index = sample['round']
            assert index not in values[arm] and -document['warmups'] <= index < document['rounds']
            command = sample['command']
            assert command[:3] == ['taskset', '-c', '2'] and command[4:] == [plan['case'], str(plan['size']), str(plan['iterations']), str(plan['seed'])]
            label, backend = arm.split('-')
            binding = document['bindings']['arms'][label]
            assert artifact(binding['manifest'])['sha256'] == binding['manifest_sha256']
            manifest = json.loads(Path(binding['manifest']).read_text())
            assert command[3] == manifest['identity']['binary_paths'][plan['group'] + '/my-' + backend]
            done = subprocess.CompletedProcess(command, sample['status'], sample['stdout'], sample['stderr'])
            checked = runner.validate(done, plan['expected'])
            assert all(sample[name] == value for name, value in checked.items())
            assert sample['host_before'] and sample['host_after']
            values[arm][index] = checked['kernel_ns']
            by_round.setdefault(index, []).append(arm)
            report['outcomes_replayed'] += 1
        for index in range(-document['warmups'], document['rounds']):
            expected_order = list(values)
            random.Random(key + '/' + str(index)).shuffle(expected_order)
            assert by_round[index] == expected_order
        for backend in ('llvm', 'qbe'):
            before = [values['before-' + backend][i] for i in range(document['rounds'])]
            after = [values['after-' + backend][i] for i in range(document['rounds'])]
            medians = [statistics.median(arm) / plan['iterations'] for arm in (before, after)]
            ratio = medians[1] / medians[0]
            assert ratio == row['after_before_ratios'][backend]
            for label, value in zip(('before', 'after'), medians):
                assert value == row['medians_ns_per_op'][label + '-' + backend]
            interval = bootstrap(after, before, key + '/' + backend)
            result = dict(case=plan['case'], profile=plan['profile'], backend=backend,
                          source_report=str(path.resolve()), before_ns=medians[0], after_ns=medians[1],
                          ratio=ratio, paired95=interval, bootstrap_seed=key + '/' + backend)
            report['rows'].append(result)
            print(key, backend, medians, ratio, interval, flush=True)
    assert artifact(path) == report['inputs'][-1]
report['status'] = 'passed'
output.write_text(json.dumps(report, indent=2) + '\n')
print('PASS saved paired streams/order/plans/medians:', report['outcomes_replayed'], 'outcomes', len(report['rows']), 'backend rows')
