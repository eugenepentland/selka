import itertools
import json
from pathlib import Path
import subprocess
import sys
import unittest
import main


def job(key, needs=()):
    return dict(id=key, duration=1, needs=list(needs))


def plan(jobs):
    return main.plan(dict(version=1, jobs=jobs))


class CycleTests(unittest.TestCase):
    def test_independent_cycles_and_downstream(self):
        jobs = [job('a', ['b']), job('b', ['a', 'root']), job('c', ['c']),
                job('d', ['a', 'c']), job('root')]
        expected = {'error': 'cycle', 'blocked': ['a', 'b', 'c', 'd'],
                    'cycles': [['a', 'b'], ['c']]}
        for permutation in itertools.permutations(jobs):
            self.assertEqual(plan(list(permutation)), expected)

    def test_cycles_merge_by_mutual_reachability(self):
        self.assertEqual(plan([job('a', ['b']), job('b', ['a', 'c']),
                               job('c', ['d']), job('d', ['c', 'a']), job('e', ['d'])]),
                         {'error': 'cycle', 'blocked': ['a', 'b', 'c', 'd', 'e'],
                          'cycles': [['a', 'b', 'c', 'd']]})

    def test_one_way_connection_preserves_groups(self):
        self.assertEqual(plan([job('a', ['b']), job('b', ['a']),
                               job('c', ['d', 'a']), job('d', ['c'])]),
                         {'error': 'cycle', 'blocked': ['a', 'b', 'c', 'd'],
                          'cycles': [['a', 'b'], ['c', 'd']]})

    def test_schema_and_error_precedence_unchanged(self):
        self.assertEqual(plan([dict(job('a'), priority=1)]), {'error': 'invalid-manifest'})
        self.assertEqual(plan([job('a', ['a']), job('b', ['missing'])]),
                         {'error': 'unknown-dependency', 'ids': ['missing']})
        self.assertEqual(plan([job('a', ['a', 'a'])]),
                         {'error': 'duplicate-dependency', 'jobs': ['a']})
        self.assertEqual(plan([job('a', ['a']), job('a')]),
                         {'error': 'duplicate-id', 'ids': ['a']})

    def test_maximum_graph_and_empty_success(self):
        ids = [f'j{i:03}' for i in range(128)]
        self.assertEqual(plan([job(key, [ids[(i+1) % 128]]) for i, key in enumerate(ids)]),
                         {'error': 'cycle', 'blocked': ids, 'cycles': [ids]})
        self.assertEqual(plan([]), dict(order=[], layers=[], timings=[], makespan=0))

    def test_success_actual_cli_has_no_cycles_field(self):
        request = {'cases': [{'version': 1, 'jobs': [job('a', ['b']), job('b')]}]}
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('main.py'))],
                                input=json.dumps(request).encode(), capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), {'results': [dict(
            order=['b', 'a'], layers=[['b'], ['a']], makespan=2,
            timings=[dict(id='a', start=1, finish=2), dict(id='b', start=0, finish=1)])]})


if __name__ == '__main__':
    unittest.main()
