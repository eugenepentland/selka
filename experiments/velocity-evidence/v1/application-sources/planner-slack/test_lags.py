"""Delayed-dependency regressions; Python only drives the .my application."""
import itertools
import unittest
from test_cli import call, job, manifest, run

def edge(id, lag):
    return {"id": id, "lag": lag}

class DependencyLags(unittest.TestCase):
    def test_branch_join_and_permutations(self):
        jobs = [job("a", 2), job("b", 5), job("c", 0, [edge("a", 10), "b"]),
                job("d", 3, [edge("c", 0), edge("b", 1)])]
        expected = dict(order=["a", "b", "c", "d"],
                        layers=[["a", "b"], ["c"], ["d"]],
                        timings=[dict(id="a", start=0, finish=2, latest_start=0, slack=0),
                                 dict(id="b", start=0, finish=5, latest_start=6, slack=6),
                                 dict(id="c", start=12, finish=12, latest_start=12, slack=0),
                                 dict(id="d", start=12, finish=15, latest_start=12, slack=0)], makespan=15, critical=["a", "c", "d"])
        cases = []
        for order in itertools.permutations(jobs):
            for reverse in (False, True):
                cases.append(manifest([job(j["id"], j["duration"],
                    j["needs"][::-1] if reverse else j["needs"]) for j in order]))
        self.assertEqual(call(dict(cases=cases)), dict(results=[expected]*len(cases)))

    def test_zero_lag_compatibility(self):
        original = [job("z", 5), job("b", 2), job("a", 3, ["b"]),
                    job("c", 0, ["a", "z"])]
        objects = [job(j["id"], j["duration"], [edge(n, 0) for n in j["needs"]])
                   for j in original]
        self.assertEqual(run(objects), run(original))

    def test_schema_and_precedence(self):
        malformed = [None, True, 0, 1.0, [], {}, {"id": "a"}, {"lag": 0},
                     {"id": "a", "lag": 0, "extra": 0}, {"id": "a", "other": 0}]
        malformed += [edge("a", v) for v in [True, False, None, 0.0, 1.5, "0",
                                             -1, 1000001, [], {}]]
        malformed += [edge(v, 0) for v in ["", "A", "0a", "a"*33, "a/b", "é",
                                           None, True, 1, {}, []]]
        cases = [manifest([job("z", needs=["missing", "missing"]), job("z"),
                           job("a", needs=[entry])]) for entry in malformed]
        self.assertEqual(call(dict(cases=cases)),
                         dict(results=[dict(error="invalid-manifest")]*len(cases)))

    def test_duplicate_unknown_and_cycle_priority(self):
        scenarios = [
            ([job("a", needs=[edge("missing", 1), "missing"]), job("a")],
             dict(error="duplicate-id", ids=["a"])),
            ([job("z", needs=["missing", edge("missing", 1)]),
              job("a", needs=[edge("x", 0), edge("x", 1000000)])],
             dict(error="duplicate-dependency", jobs=["a", "z"])),
            ([job("b", needs=[edge("x", 7), "a"]), job("c", needs=[edge("x", 0)])],
             dict(error="unknown-dependency", ids=["a", "x"])),
            ([job("a", 0, [edge("a", 0)]), job("b", 0, [edge("a", 1000000)]),
              job("c")], dict(error="cycle", blocked=["a", "b"])),
            ([job("a", 0, [edge("b", 0)]), job("b", 0, [edge("a", 0)]),
              job("c", needs=[edge("unknown", 1)])],
             dict(error="unknown-dependency", ids=["unknown"])),
        ]
        cases, expected = [], []
        for jobs, result in scenarios:
            for order in (jobs, jobs[::-1]):
                cases.append(manifest(order))
                expected.append(result)
        self.assertEqual(call(dict(cases=cases)), dict(results=expected))

    def test_decoded_identifiers_and_keys(self):
        raw = br'{"cases":[{"version":1,"jobs":[{"id":"a","duration":0,"needs":[]},{"id":"b","duration":0,"needs":["a",{"i\u0064":"\u0061","l\u0061g":1}]}]}]}'
        self.assertEqual(call(raw, True),
                         dict(results=[dict(error="duplicate-dependency", jobs=["b"])]))
        raw = br'{"cases":[{"version":1,"jobs":[{"id":"a","duration":0,"needs":[{"id":"a","lag":0,"l\u0061g":1}]}]}]}'
        self.assertEqual(call(raw, True), dict(error="invalid-request"))

    def test_maximum_chain_and_identifier(self):
        names = ["j"+str(i).zfill(3) for i in range(128)]
        jobs = [job(n, 1000000, [] if i == 0 else [edge(names[i-1], 1000000)])
                for i, n in enumerate(names)]
        expected = dict(order=names, layers=[[n] for n in names],
                        timings=[dict(id=n, start=i*2000000, finish=i*2000000+1000000,
                                      latest_start=i*2000000, slack=0)
                                 for i, n in enumerate(names)], makespan=255000000, critical=names)
        self.assertEqual(run(jobs[::-1]), expected)
        long_id = "a" + "0_-"*10 + "z"
        self.assertEqual(run([job(long_id, 0), job("b", 0, [edge(long_id, 1000000)])])
                         ["makespan"], 1000000)
        self.assertEqual(run([job("a", needs=[edge("x"+str(i), 0) for i in range(129)])]),
                         dict(error="invalid-manifest"))

    def test_maximum_dependency_array(self):
        needs = [edge("x"+str(i).zfill(3), 1000000) for i in range(128)]
        self.assertEqual(run([job("a", needs=needs)]),
                         dict(error="unknown-dependency", ids=[e["id"] for e in needs]))

if __name__ == "__main__":
    unittest.main()
