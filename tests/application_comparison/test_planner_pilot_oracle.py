import copy
import itertools
import unittest
from experiments.application_comparison import planner_oracle as base
from experiments.application_comparison import planner_pilot_oracle as pilot


def graphs():
    names = ('a', 'b', 'c')
    for mask in range(512):
        yield {'version': 1, 'jobs': [dict(id=name, duration=index + 1,
            needs=[other for target, other in enumerate(names) if mask & (1 << (index * 3 + target))])
            for index, name in enumerate(names)]}


class PlannerPilotTests(unittest.TestCase):
    def test_cycle_groups_against_independent_graph_search(self):
        for manifest in graphs():
            original = base.manifest_result(manifest)
            actual = pilot.cycle_groups_result(manifest)
            if original.get('error') != 'cycle':
                self.assertEqual(actual, original)
                continue
            edges = {job['id']: job['needs'] for job in manifest['jobs']}
            def reachable(source, target):
                pending = list(edges[source])
                visited = set()
                while pending:
                    node = pending.pop()
                    if node == target:
                        return True
                    if node not in visited:
                        visited.add(node)
                        pending.extend(edges[node])
                return False
            expected = {tuple(sorted(other for other in edges
                                    if reachable(name, other) and reachable(other, name)))
                        for name in edges if reachable(name, name)}
            self.assertEqual(actual, dict(original, cycles=[list(group) for group in sorted(expected)]))

    def test_priority_against_exhaustive_valid_orders(self):
        for manifest in graphs():
            original = base.manifest_result(manifest)
            self.assertEqual(pilot.priority_result(manifest), original)
            if 'error' in original:
                continue
            valid_orders = [order for order in itertools.permutations(('a', 'b', 'c'))
                            if all(order.index(need) < order.index(job['id'])
                                   for job in manifest['jobs'] for need in job['needs'])]
            for priorities in itertools.product((-1, 0, 1), repeat=3):
                edited = copy.deepcopy(manifest)
                ranks = {}
                for job, priority in zip(edited['jobs'], priorities):
                    job['priority'] = priority
                    ranks[job['id']] = (-priority, job['id'])
                expected = min(valid_orders, key=lambda order: tuple(ranks[name] for name in order))
                self.assertEqual(pilot.priority_result(edited), dict(original, order=list(expected)))

    def test_schema_precedence_and_task_separation(self):
        original = {'version': 1, 'jobs': [dict(id='a', duration=0, needs=[])]}
        for value in (True, 0.0, None, -1001, 1001, '1'):
            manifest = copy.deepcopy(original)
            manifest['jobs'][0]['priority'] = value
            self.assertEqual(pilot.priority_result(manifest), {'error': 'invalid-manifest'})
        for value in (-1000, 1000):
            manifest = copy.deepcopy(original)
            manifest['jobs'][0]['priority'] = value
            before = copy.deepcopy(manifest)
            self.assertEqual(pilot.priority_result(manifest), base.manifest_result(original))
            self.assertEqual(manifest, before)
            self.assertEqual(pilot.cycle_groups_result(manifest), {'error': 'invalid-manifest'})
        manifest['jobs'].append(dict(manifest['jobs'][0], needs=['absent']))
        self.assertEqual(pilot.priority_result(manifest), {'error': 'duplicate-id', 'ids': ['a']})

    def test_raw_boundary_and_duplicate_keys(self):
        valid = b'{"cases":[]}'
        for task in pilot.HANDLERS:
            self.assertEqual(pilot.response_bytes(valid + b' ' * (1048576 - len(valid)), task), {'results': []})
            self.assertEqual(pilot.response_bytes(valid + b' ' * (1048577 - len(valid)), task), {'error': 'invalid-request'})
            self.assertEqual(pilot.response_bytes(b'{"cases":[],"cases":[]}', task), {'error': 'invalid-request'})


if __name__ == '__main__':
    unittest.main()
