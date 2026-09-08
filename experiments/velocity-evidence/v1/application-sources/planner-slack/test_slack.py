"""Slack regressions; enumerate feasible schedules independently on small DAGs."""
import itertools
import random
import unittest
from test_cli import call, job, manifest, run

def edge(name, lag):
    return dict(id=name, lag=lag)

class Slack(unittest.TestCase):
    def test_join_disconnected_and_zero_duration(self):
        jobs = [job("z", 1), job("b", 5), job("a", 2),
                job("c", 0, ["a", edge("b", 1)])]
        expected = dict(order=["a", "b", "c", "z"],
                        layers=[["a", "b", "z"], ["c"]], makespan=6,
                        critical=["b", "c"],
                        timings=[dict(id="a", start=0, finish=2, latest_start=4, slack=4),
                                 dict(id="b", start=0, finish=5, latest_start=0, slack=0),
                                 dict(id="c", start=6, finish=6, latest_start=6, slack=0),
                                 dict(id="z", start=0, finish=1, latest_start=5, slack=5)])
        cases = [manifest([job(j["id"], j["duration"], j["needs"][::direction])
                           for j in order])
                 for order in itertools.permutations(jobs) for direction in (1, -1)]
        self.assertEqual(call(dict(cases=cases)), dict(results=[expected] * len(cases)))

    def test_multiple_critical_paths_and_zero_chains(self):
        result = run([job("a", 2), job("b", 3), job("c", 1, ["a"]),
                      job("d", 0, ["b", "c"]), job("e", 0, ["d"])])
        self.assertEqual(result["critical"], ["a", "b", "c", "d", "e"])
        self.assertEqual([t["latest_start"] for t in result["timings"]], [0, 0, 2, 3, 3])
        result = run([job("z", 0), job("a", 0, ["z"]), job("b", 0, ["a"])])
        self.assertEqual(result["critical"], ["a", "b", "z"])
        self.assertTrue(all(t["slack"] == t["latest_start"] == 0 for t in result["timings"]))

    def test_exhaustive_feasible_schedules(self):
        rng = random.Random(72503)
        graphs = []
        for _ in range(24):
            names = ["z", "a", "m"]
            jobs = [job(name, rng.randrange(3),
                        [edge(names[k], rng.randrange(3)) for k in range(i)
                         if rng.randrange(2)]) for i, name in enumerate(names)]
            graphs.append(jobs)
        results = call(dict(cases=[manifest(jobs[::-1]) for jobs in graphs]))["results"]
        for jobs, result in zip(graphs, results):
            # Enumerate every schedule through a known safe bound, find the
            # optimal deadline, then extrema over all schedules meeting it.
            bounds = sum(j["duration"] for j in jobs) + sum(
                e["lag"] for j in jobs for e in j["needs"])
            index = {j["id"]: i for i, j in enumerate(jobs)}
            feasible = []
            for starts in itertools.product(range(bounds + 1), repeat=len(jobs)):
                if all(starts[i] >= starts[index[e["id"]]] +
                       jobs[index[e["id"]]]["duration"] + e["lag"]
                       for i, j in enumerate(jobs) for e in j["needs"]):
                    deadline = max(starts[i] + j["duration"] for i, j in enumerate(jobs))
                    feasible.append((deadline, starts))
            best = min(deadline for deadline, _ in feasible)
            optimal = [s for deadline, s in feasible if deadline == best]
            self.assertEqual(result["makespan"], best)
            expected_critical = []
            for timing in result["timings"]:
                i = index[timing["id"]]
                early = min(s[i] for s in optimal)
                latest = max(s[i] for s in optimal)
                self.assertEqual(timing, dict(id=jobs[i]["id"], start=early,
                    finish=early + jobs[i]["duration"], latest_start=latest, slack=latest-early))
                if latest == early:
                    expected_critical.append(jobs[i]["id"])
            self.assertEqual(result["critical"], sorted(expected_critical))

    def test_dense_dag_maximum_lags(self):
        names = ["j" + str(i).zfill(3) for i in range(128)]
        jobs = [job(name, 1000000, [edge(p, 1000000) for p in names[:i]])
                for i, name in enumerate(names)]
        result = run(jobs[::-1])
        self.assertEqual(result["makespan"], 255000000)
        self.assertEqual(result["critical"], names)
        self.assertEqual(result["timings"], [
            dict(id=name, start=i*2000000, finish=i*2000000+1000000,
                 latest_start=i*2000000, slack=0) for i, name in enumerate(names)])

if __name__ == "__main__":
    unittest.main()
