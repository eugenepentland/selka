import itertools
import json
import random
import unittest
from experiments.application_comparison.planner_oracle import (
    generated_cases, manifest_result, response, response_bytes,
)


def job(name, duration=1, needs=()):
    return {'id': name, 'duration': duration, 'needs': list(needs)}


def plan(jobs):
    return manifest_result({'version': 1, 'jobs': jobs})


class PlannerOracleTests(unittest.TestCase):
    def test_documented_example_and_empty(self):
        self.assertEqual(plan([job('z', 5), job('b', 2), job('a', 3, ['b'])]), {
            'order': ['b', 'a', 'z'], 'layers': [['b', 'z'], ['a']],
            'timings': [{'id': 'a', 'start': 2, 'finish': 5},
                        {'id': 'b', 'start': 0, 'finish': 2},
                        {'id': 'z', 'start': 0, 'finish': 5}], 'makespan': 5})
        self.assertEqual(plan([]), {'order': [], 'layers': [], 'timings': [], 'makespan': 0})

    def test_validation_precedence_and_cycle_downstream(self):
        self.assertEqual(plan([job('a'), job('a', -1)]), {'error': 'invalid-manifest'})
        self.assertEqual(plan([job('a', needs=['x', 'x']), job('a')]),
                         {'error': 'duplicate-id', 'ids': ['a']})
        self.assertEqual(plan([job('a', needs=['x', 'x'])]),
                         {'error': 'duplicate-dependency', 'jobs': ['a']})
        self.assertEqual(plan([job('a', needs=['a', 'x'])]),
                         {'error': 'unknown-dependency', 'ids': ['x']})
        self.assertEqual(plan([job('a', needs=['b']), job('b', needs=['a']),
                               job('c', needs=['b']), job('d')]),
                         {'error': 'cycle', 'blocked': ['a', 'b', 'c']})

    def test_all_three_vertex_graphs_against_permutation_and_path_oracles(self):
        # Exhaust all 512 directed graphs, including self edges. The independent
        # specification enumerates valid permutations and prerequisite paths;
        # it does not reuse the production oracle's ready-set removal algorithm.
        names = ['a', 'b', 'c']
        edges = list(itertools.product(names, repeat=2))
        for mask in range(1 << len(edges)):
            needs = {name: [] for name in names}
            for bit, (name, prior) in enumerate(edges):
                if mask & (1 << bit):
                    needs[name].append(prior)
            durations = {'a': 0, 'b': 2, 'c': 5}
            result = plan([job(name, durations[name], needs[name]) for name in names])
            valid = [p for p in itertools.permutations(names)
                     if all(p.index(prior) < p.index(name) for name in names for prior in needs[name])]

            def paths(name, visited=()):
                if name in visited:
                    return None
                children = [paths(prior, visited + (name,)) for prior in needs[name]]
                if any(child is None for child in children):
                    return None
                return (durations[name] + max((child[0] for child in children), default=0),
                        1 + max((child[1] for child in children), default=0))

            derived = {name: paths(name) for name in names}
            if not valid:
                self.assertEqual(result, {'error': 'cycle', 'blocked':
                                          [name for name in names if derived[name] is None]}, mask)
                continue
            self.assertEqual(result['order'], list(min(valid)), mask)
            self.assertEqual(result['makespan'], max(item[0] for item in derived.values()), mask)
            self.assertEqual(result['timings'], [
                {'id': name, 'start': derived[name][0] - durations[name], 'finish': derived[name][0]}
                for name in names], mask)
            self.assertEqual(result['layers'], [
                [name for name in names if derived[name][1] == level]
                for level in range(1, max(item[1] for item in derived.values()) + 1)], mask)

    def test_schema_transport_and_bounds(self):
        for duration in [True, 1.0, -1, 1000001, '2', None]:
            self.assertEqual(plan([job('a', duration)]), {'error': 'invalid-manifest'})
        for name in ['', 'A', 'a' * 33, 'a\n', 'é']:
            self.assertEqual(plan([job(name)]), {'error': 'invalid-manifest'})
        for raw in [b'{}', b'{"cases":[],"cases":[]}', b'{"cases":[NaN]}',
                    b'{"cases":[1e400]}', b'{"cases":[9223372036854775808]}',
                    b'\xff', b'{', b' ' * (1024 * 1024 + 1)]:
            self.assertEqual(response_bytes(raw), {'error': 'invalid-request'})
        self.assertEqual(response({'cases': [None]}), {'results': [{'error': 'invalid-manifest'}]})
        self.assertEqual(response({'cases': []}), {'results': []})
        self.assertEqual(response({'cases': [None] * 65}), {'error': 'invalid-request'})
        chain = [job(f'j{i:03}', 1000000, [f'j{i-1:03}'] if i else []) for i in range(128)]
        self.assertEqual(plan(chain)['makespan'], 128000000)
        self.assertEqual(plan(chain + [job('extra')]), {'error': 'invalid-manifest'})

    def test_generation_reproducibility_and_input_order_invariance(self):
        request = generated_cases(98234)
        self.assertEqual(request, generated_cases(98234))
        self.assertNotEqual(request, generated_cases(98235))
        original = response(request)
        self.assertEqual(response_bytes(json.dumps(request).encode()), original)
        rng = random.Random(10)
        for manifest in request['cases']:
            rng.shuffle(manifest['jobs'])
            for item in manifest['jobs']:
                rng.shuffle(item['needs'])
        self.assertEqual(response(request), original)
        self.assertEqual({r.get('error', 'success') for r in original['results']}, {
            'success', 'cycle', 'unknown-dependency', 'duplicate-id',
            'duplicate-dependency', 'invalid-manifest'})


if __name__ == '__main__':
    unittest.main()
