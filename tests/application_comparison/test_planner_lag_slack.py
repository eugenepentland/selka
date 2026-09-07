"""Independent public expectations and exhaustive tiny-schedule oracle checks."""
import base64
import copy
import itertools
import json
import unittest

from experiments.application_comparison import pilot_cases
from experiments.application_comparison import planner_oracle as base
from experiments.application_comparison import planner_pilot_oracle as oracle


def job(name, duration, needs=()):
    return dict(id=name, duration=duration, needs=list(needs))


def manifest(*jobs):
    return dict(version=1, jobs=list(jobs))


class LagSlackTests(unittest.TestCase):
    def test_explicit_lag_join_and_disconnected_slack(self):
        value = manifest(job('a', 2), job('b', 5),
                         job('c', 0, ['a', dict(id='b', lag=1)]), job('z', 1))
        expected = dict(order=['a', 'b', 'c', 'z'], layers=[['a', 'b', 'z'], ['c']],
                        timings=[dict(id='a', start=0, finish=2), dict(id='b', start=0, finish=5),
                                 dict(id='c', start=6, finish=6), dict(id='z', start=0, finish=1)],
                        makespan=6)
        self.assertEqual(oracle.dependency_lags_result(value), expected)
        latest = [4, 0, 6, 5]
        self.assertEqual(oracle.slack_result(value), dict(expected,
            timings=[dict(t, latest_start=ls, slack=ls-t['start'])
                     for t, ls in zip(expected['timings'], latest)], critical=['b', 'c']))

    def test_empty_and_zero_duration_lag(self):
        self.assertEqual(oracle.slack_result(manifest()),
                         dict(order=[], layers=[], timings=[], makespan=0, critical=[]))
        result = oracle.slack_result(manifest(job('a', 0), job('b', 0, [dict(id='a', lag=1000000)])))
        self.assertEqual(result['makespan'], 1000000)
        self.assertEqual(result['timings'], [dict(id='a', start=0, finish=0, latest_start=0, slack=0),
                                            dict(id='b', start=1000000, finish=1000000,
                                                 latest_start=1000000, slack=0)])
        self.assertEqual(result['critical'], ['a', 'b'])

    def test_exhaustive_feasible_schedules(self):
        # Enumerate schedules rather than reuse either a forward/backward graph
        # recurrence. Greatest per-job feasible start must equal oracle latest.
        for durations in itertools.product((0, 1), repeat=3):
            for choices in itertools.product((None, 0, 1), repeat=3):
                needs = [[], [], []]
                edges = []
                for (source, target), lag in zip(((0, 1), (0, 2), (1, 2)), choices):
                    if lag is not None:
                        needs[target].append(dict(id='abc'[source], lag=lag))
                        edges.append((source, target, lag))
                value = manifest(*(job(name, duration, dependencies)
                                   for name, duration, dependencies in zip('abc', durations, needs)))
                actual = oracle.slack_result(value)
                deadline = actual['makespan']
                feasible = [starts for starts in itertools.product(
                    *(range(deadline-duration+1) for duration in durations))
                    if all(starts[target] >= starts[source]+durations[source]+lag
                           for source, target, lag in edges)]
                self.assertTrue(feasible)
                self.assertEqual(deadline, min(max(start+duration for start, duration in zip(starts, durations))
                                               for starts in feasible))
                for index, timing in enumerate(actual['timings']):
                    self.assertEqual(timing['start'], min(starts[index] for starts in feasible))
                    self.assertEqual(timing['latest_start'], max(starts[index] for starts in feasible))
                    self.assertEqual(timing['slack'], timing['latest_start']-timing['start'])
                latest = [t['latest_start'] for t in actual['timings']]
                self.assertTrue(all(latest[v] >= latest[u]+durations[u]+lag for u, v, lag in edges))

    def test_representation_equivalence_and_no_mutation(self):
        for value in base.generated_cases('lag-unit-original', 64)['cases']:
            original = copy.deepcopy(value)
            self.assertEqual(oracle.dependency_lags_result(value), base.manifest_result(value))
            explicit = copy.deepcopy(value)
            for entry in explicit['jobs']:
                entry['needs'] = [dict(id=name, lag=0) for name in entry['needs']]
            self.assertEqual(oracle.dependency_lags_result(explicit), base.manifest_result(value))
            self.assertEqual(value, original)
        value = manifest(job('a', 3), job('b', 0, [dict(id='a', lag=2)]), job('c', 2, ['a']))
        expected = oracle.slack_result(value)
        for jobs in itertools.permutations(value['jobs']):
            self.assertEqual(oracle.slack_result(manifest(*jobs)), expected)

    def test_schema_precedence_and_resolved_identifiers(self):
        for handler in (oracle.dependency_lags_result, oracle.slack_result):
            for edge in (None, True, [], dict(id='a'), dict(lag=1), dict(id='a', lag=True),
                         dict(id='a', lag=0.0), dict(id='a', lag=None), dict(id='a', lag=-1),
                         dict(id='a', lag=1000001), dict(id='A', lag=0), dict(id='a', lag=0, extra=1)):
                self.assertEqual(handler(manifest(job('a', 0), job('a', 1, [edge]))),
                                 {'error': 'invalid-manifest'})
            self.assertEqual(handler(manifest(job('a', 0), job('a', 1, ['missing', 'missing']))),
                             {'error': 'duplicate-id', 'ids': ['a']})
            self.assertEqual(handler(manifest(job('a', 0), job('b', 1, ['a', dict(id='a', lag=9)]))),
                             {'error': 'duplicate-dependency', 'jobs': ['b']})
            self.assertEqual(handler(manifest(job('a', 0, ['a', dict(id='missing', lag=0)]))),
                             {'error': 'unknown-dependency', 'ids': ['missing']})
            self.assertEqual(handler(manifest(job('a', 0, [dict(id='a', lag=0)]), job('b', 1, ['a']))),
                             {'error': 'cycle', 'blocked': ['a', 'b']})
            self.assertEqual(handler(manifest(dict(job('a', 0), priority=0))), {'error': 'invalid-manifest'})

    def test_pack_limits_determinism_and_strict_transport(self):
        for task in ('planner-dependency-lags', 'planner-slack'):
            cases = pilot_cases.build(task, seed='lag-test')
            self.assertEqual(cases, pilot_cases.build(task, seed='lag-test'))
            self.assertNotEqual(cases, pilot_cases.build(task, seed='lag-test-other'))
            self.assertEqual(len(pilot_cases.build(task, seed='lag-test', public=True)), 2)
            for entry in cases:
                case = entry['case']
                if 'request' in case:
                    self.assertLessEqual(len(case['request']['cases']), 64)
                    self.assertLessEqual(len(json.dumps(case['request']).encode()), 1048576)
                else:
                    data = base64.b64decode(case['request_base64'])
                    self.assertEqual(oracle.response_bytes(data, task), {'error': 'invalid-request'})
            packed = {entry['name']: entry['case'] for entry in cases}
            large = packed['maximum-chain-and-dense-graphs']['expected']['results']
            self.assertEqual(large[0]['makespan'], 255000000)
            self.assertEqual(len(large[0]['timings']), 128)
            self.assertEqual(large[2], {'error': 'cycle', 'blocked': [f'n{i:03}' for i in range(128)]})
            self.assertEqual(len(packed['maximum-manifest-batch']['request']['cases']), 64)
            for raw in (b'{"cases":[]}', b'{"cases":[]}'+b' '*1048564):
                self.assertEqual(oracle.response_bytes(raw, task), {'results': []})
            self.assertEqual(oracle.response_bytes(b'{"cases":[]}'+b' '*1048565, task),
                             {'error': 'invalid-request'})


if __name__ == '__main__':
    unittest.main()
