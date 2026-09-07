"""Independent bounded schedule enumeration for the delayed-dependency chain.

This test does not use forward/backward dynamic programming to derive expected
start/slack values. It enumerates feasible schedules under one common deadline.
"""
import itertools
import random
import unittest
from experiments.application_comparison import planner_pilot_oracle as oracle


def enumerated_schedule(durations, edges):
    n = len(durations)
    horizon = sum(durations) + sum(lag for _, _, lag in edges)
    schedules = []
    best = horizon
    for starts in itertools.product(range(horizon + 1), repeat=n):
        finish = tuple(starts[i] + durations[i] for i in range(n))
        if any(starts[v] < finish[u] + lag for u, v, lag in edges):
            continue
        deadline = max(finish, default=0)
        if deadline > best:
            continue
        if deadline < best:
            best = deadline
            schedules = []
        schedules.append(starts)
    assert schedules
    earliest = [min(s[i] for s in schedules) for i in range(n)]
    latest = [max(s[i] for s in schedules) for i in range(n)]
    return best, earliest, latest


class ChainScheduleReference(unittest.TestCase):
    def test_against_independent_feasible_schedule_enumeration(self):
        rng = random.Random('independent-schedule-enumeration-v1')
        for case in range(96):
            n = 1 + case % 3
            durations = [rng.randrange(3) for _ in range(n)]
            topology = list(range(n))
            rng.shuffle(topology)
            edges = [(u, v, rng.randrange(3)) for i, u in enumerate(topology)
                     for v in topology[i + 1:] if rng.randrange(2)]
            deadline, earliest, latest = enumerated_schedule(durations, edges)
            names = [f'j{i}' for i in range(n)]
            jobs = []
            for i in range(n):
                needs = [names[u] if lag == 0 and rng.randrange(2) else {'id': names[u], 'lag': lag}
                         for u, v, lag in edges if v == i]
                rng.shuffle(needs)
                jobs.append({'id': names[i], 'duration': durations[i], 'needs': needs})
            rng.shuffle(jobs)
            value = {'version': 1, 'jobs': jobs}
            with self.subTest(case=case, jobs=jobs):
                lag = oracle.HANDLERS['planner-dependency-lags'](value)
                slack = oracle.HANDLERS['planner-slack'](value)
                self.assertEqual(lag['makespan'], deadline)
                self.assertEqual(lag['timings'], [{'id': names[i], 'start': earliest[i],
                                                  'finish': earliest[i] + durations[i]} for i in range(n)])
                self.assertEqual(slack['timings'], [{'id': names[i], 'start': earliest[i],
                    'finish': earliest[i] + durations[i], 'latest_start': latest[i],
                    'slack': latest[i] - earliest[i]} for i in range(n)])
                self.assertEqual(slack['critical'], [names[i] for i in range(n) if latest[i] == earliest[i]])
                for key in ('order', 'layers', 'makespan'):
                    self.assertEqual(slack[key], lag[key])


if __name__ == '__main__':
    unittest.main()
