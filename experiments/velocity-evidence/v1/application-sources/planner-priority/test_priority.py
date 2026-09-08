"""Priority policy regressions; Python only drives the .my application."""
import itertools
import unittest
from test_cli import call, job, manifest

class Priority(unittest.TestCase):
    def test_ready_selection_and_permutations(self):
        # b wins initially; completing b releases a ahead of already-ready z.
        jobs = [dict(job("z", 5), priority=-1),
                dict(job("b", 2), priority=-1),
                dict(job("a", 3, ["b"]), priority=1000),
                job("c", 0, ["a", "z"])]
        expected = dict(order=["b", "a", "z", "c"],
                        layers=[["b", "z"], ["a"], ["c"]],
                        timings=[dict(id="a", start=2, finish=5),
                                 dict(id="b", start=0, finish=2),
                                 dict(id="c", start=5, finish=5),
                                 dict(id="z", start=0, finish=5)], makespan=5)
        cases = []
        for order in itertools.permutations(jobs):
            for needs in (["a", "z"], ["z", "a"]):
                cases.append(manifest([dict(j, needs=needs) if j["id"] == "c"
                                       else j for j in order]))
        self.assertEqual(call(dict(cases=cases)),
                         dict(results=[expected] * len(cases)))

    def test_defaults_negative_ties_and_boundaries(self):
        jobs = [dict(job("a"), priority=-1000), job("z"),
                dict(job("b"), priority=0), dict(job("c"), priority=1000)]
        result = call(dict(cases=[manifest(jobs)]))["results"][0]
        self.assertEqual(result["order"], ["c", "b", "z", "a"])
        self.assertEqual(result["layers"], [["a", "b", "c", "z"]])
        explicit = [dict(j, priority=j.get("priority", 0)) for j in jobs]
        self.assertEqual(call(dict(cases=[manifest(explicit)]))["results"][0], result)

    def test_cycle_and_validation_precedence(self):
        cycle = [dict(job("z", needs=["y"]), priority=1000),
                 dict(job("y", needs=["z"]), priority=-1000),
                 dict(job("a", needs=["z"]), priority=1000), job("b")]
        cases = [manifest(list(order)) for order in itertools.permutations(cycle)]
        self.assertEqual(call(dict(cases=cases)),
                         dict(results=[dict(error="cycle", blocked=["a", "y", "z"])]*24))
        cases = [manifest([dict(job("b"), priority=1000),
                           dict(job("b"), priority=-1), dict(job("a"), priority=None)]),
                 manifest([dict(job("b"), priority=1000), dict(job("b"), priority=-1)]),
                 manifest([dict(job("z", needs=["missing", "missing"]), priority=1000),
                           dict(job("a", needs=["x", "x"]), priority=-1000)])]
        self.assertEqual(call(dict(cases=cases)), dict(results=[
            dict(error="invalid-manifest"), dict(error="duplicate-id", ids=["b"]),
            dict(error="duplicate-dependency", jobs=["a", "z"])]))

    def test_schema_and_transport(self):
        cases = [manifest([dict(job("a"), priority=value)])
                 for value in [True, False, 0.0, 1e3, None, "0", [], {}, -1001, 1001]]
        for missing in ["id", "duration", "needs"]:
            j = dict(job("a"), priority=0)
            del j[missing]
            cases.append(manifest([j]))
        cases.extend([manifest([dict(job("a"), extra=0)]),
                      manifest([dict(job("a"), priority=0, extra=0)])])
        self.assertEqual(call(dict(cases=cases)),
                         dict(results=[dict(error="invalid-manifest")]*len(cases)))
        raw = b'{"cases":[{"version":1,"jobs":[{"id":"a","duration":0,"needs":[],"priority":0,"priority":1}]}]}'
        self.assertEqual(call(raw, True), dict(error="invalid-request"))
        escaped = raw.replace(b'"priority":1', b'"pri' + bytes([92]) + b'u006frity":1')
        self.assertEqual(call(escaped, True), dict(error="invalid-request"))
        for value in [b"9223372036854775808", b"-9223372036854775809"]:
            self.assertEqual(call(raw.replace(b'"priority":0,"priority":1',
                                             b'"priority":' + value), True),
                             dict(error="invalid-request"))

if __name__ == "__main__":
    unittest.main()
