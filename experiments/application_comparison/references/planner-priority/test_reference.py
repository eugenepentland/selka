import itertools
import json
from pathlib import Path
import subprocess
import sys
import unittest
import main


def job(key, needs=(), **extra):
    return dict(id=key, duration=2, needs=list(needs), **extra)


def plan(jobs):
    return main.plan(dict(version=1, jobs=jobs))


class PriorityTests(unittest.TestCase):
    def test_newly_ready_and_report_independence(self):
        jobs = [job('a', priority=-10), job('b', priority=3),
                job('c', ['b'], priority=1000), job('d', priority=3)]
        expected = dict(order=['b', 'c', 'd', 'a'],
                        layers=[['a', 'b', 'd'], ['c']],
                        timings=[dict(id=k, start=s, finish=s+2)
                                 for k, s in [('a', 0), ('b', 0), ('c', 2), ('d', 0)]],
                        makespan=4)
        for permutation in itertools.permutations(jobs):
            self.assertEqual(plan(list(permutation)), expected)

    def test_defaults_ties_and_extremes(self):
        self.assertEqual(plan([job('z', priority=-1000), job('b'),
                               job('a', priority=0), job('c', priority=1000)])['order'],
                         ['c', 'a', 'b', 'z'])

    def test_schema_and_transport(self):
        for value in [True, False, None, 1.0, '1', -1001, 1001]:
            self.assertEqual(plan([job('a', priority=value)]), {'error': 'invalid-manifest'})
        for field in ['id', 'duration', 'needs']:
            broken = job('a', priority=1)
            del broken[field]
            self.assertEqual(plan([broken]), {'error': 'invalid-manifest'})
        self.assertEqual(plan([job('a', extra=0)]), {'error': 'invalid-manifest'})
        self.assertEqual(main.respond(b'{"cases":[{"version":1,"jobs":[{"id":"a","duration":0,"needs":[],"priority":1,"priority":2}]}]}'),
                         {'error': 'invalid-request'})

    def test_precedence_and_cycles(self):
        self.assertEqual(plan([job('a', ['missing']), job('a', priority=5)]),
                         {'error': 'duplicate-id', 'ids': ['a']})
        self.assertEqual(plan([job('a', ['b'], priority=1000), job('b', ['a']),
                               job('c', ['b']), job('z')]),
                         {'error': 'cycle', 'blocked': ['a', 'b', 'c']})

    def test_old_example_actual_cli(self):
        request = {'cases': [{'version': 1, 'jobs': [
            dict(id='z', duration=5, needs=[]), dict(id='b', duration=2, needs=[]),
            dict(id='a', duration=3, needs=['b'])]}]}
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('main.py'))],
                                input=json.dumps(request).encode(), capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), {'results': [dict(
            order=['b', 'a', 'z'], layers=[['b', 'z'], ['a']], makespan=5,
            timings=[dict(id='a', start=2, finish=5), dict(id='b', start=0, finish=2),
                     dict(id='z', start=0, finish=5)])]})


if __name__ == '__main__':
    unittest.main()
