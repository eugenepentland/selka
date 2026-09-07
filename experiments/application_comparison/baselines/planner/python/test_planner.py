"""Independent contract examples and invariants; no oracle dependency."""

import itertools
import json
import unittest

from planner import MAX_INPUT_BYTES, plan, respond


def job(key, duration=1, needs=()):
    return {"id": key, "duration": duration, "needs": list(needs)}


def manifest(*jobs):
    return {"version": 1, "jobs": list(jobs)}


class TransportTests(unittest.TestCase):
    def test_invalid_envelopes(self):
        for value in [None, [], {}, {"cases": {}}, {"cases": [], "extra": 0},
                      {"cases": [None] * 65}]:
            with self.subTest(value=value):
                self.assertEqual(respond(json.dumps(value).encode()), {"error": "invalid-request"})

    def test_global_parse_errors_discard_other_results(self):
        for payload in [b'{"cases": [], "cases": []}', b'{"cases":[{"x":0,"x":1}]}',
                        b'{"cases":[9223372036854775808]}',
                        b'{"cases":[-9223372036854775809]}',
                        b'{"cases":[NaN]}', b'{"cases":[Infinity]}',
                        b'{"cases":[1e999]}', b'{"cases":["\xff"]}',
                        b'{"cases":[]} trailing', b'']:
            with self.subTest(payload=payload):
                self.assertEqual(respond(payload), {"error": "invalid-request"})

    def test_int64_boundaries_are_valid_transport(self):
        self.assertEqual(respond(b'{"cases":[9223372036854775807,-9223372036854775808]}'),
                         {"results": [{"error": "invalid-manifest"}] * 2})

    def test_byte_limit(self):
        request = b'{"cases":[]}'
        self.assertEqual(respond(request + b' ' * (MAX_INPUT_BYTES - len(request))), {"results": []})
        self.assertEqual(respond(request + b' ' * (MAX_INPUT_BYTES + 1 - len(request))),
                         {"error": "invalid-request"})

    def test_manifest_failures_are_independent_and_ordered(self):
        self.assertEqual(respond(b'{"cases":[null,{"version":1,"jobs":[]}]}'),
                         {"results": [{"error": "invalid-manifest"}, plan(manifest())]})

    def test_container_depth_boundary_precedes_schema_validation(self):
        # The envelope object and cases array already account for two levels.
        for wrapper in [lambda item: [item], lambda item: {"x": item}]:
            item = 0
            for _ in range(62):
                item = wrapper(item)
            self.assertEqual(respond(json.dumps({"cases": [item]}).encode()),
                             {"results": [{"error": "invalid-manifest"}]})
            item = wrapper(item)
            self.assertEqual(respond(json.dumps({"cases": [item]}).encode()),
                             {"error": "invalid-request"})

    def test_container_depth_ignores_string_delimiters_and_escapes(self):
        for text in ['[{' * 100, '\\"[{' * 100, '\\\\' * 100, '}]' * 100]:
            with self.subTest(text=text):
                payload = json.dumps({"cases": [text]}).encode()
                self.assertEqual(respond(payload), {"results": [{"error": "invalid-manifest"}]})

    def test_excessive_depth_is_rejected_before_recursive_parser(self):
        payload = b'{"cases":[' + b'[' * 10000 + b'0' + b']' * 10000 + b']}'
        self.assertEqual(respond(payload), {"error": "invalid-request"})

    def test_unpaired_surrogates_are_global_errors_in_keys_and_values(self):
        escapes = [b'\\ud800', b'\\udfff', b'\\ud800\\ud800', b'\\udfff\\ud800']
        for escape in escapes:
            for payload in [b'{"cases":["' + escape + b'"]}',
                            b'{"cases":[{"' + escape + b'":0}]}',
                            b'{"cases":[{"version":1,"jobs":[]},{"x":["' + escape + b'"]}]}']:
                with self.subTest(payload=payload):
                    self.assertEqual(respond(payload), {"error": "invalid-request"})

    def test_paired_surrogates_and_scalar_boundaries_pass_transport(self):
        for escaped in [b'\\ud83d\\ude00', b'\\ud800\\udc00', b'\\udbff\\udfff',
                        b'\\ud7ff', b'\\ue000', b'\\uffff', b'\\u0000']:
            for payload in [b'{"cases":["' + escaped + b'"]}',
                            b'{"cases":[{"' + escaped + b'":0}]}']:
                with self.subTest(payload=payload):
                    self.assertEqual(respond(payload), {"results": [{"error": "invalid-manifest"}]})
        self.assertEqual(respond('{"cases":["😀"]}'.encode()),
                         {"results": [{"error": "invalid-manifest"}]})


class ValidationTests(unittest.TestCase):
    def test_schema_types_and_bounds(self):
        invalid = [None, {"version": True, "jobs": []}, {"version": 1.0, "jobs": []},
                   {"version": 1, "jobs": [], "extra": 0}, manifest(*([job("a")] * 129))]
        invalid += [manifest(job(key)) for key in ["", "A", "é", "a\n", "a" * 33, "0a"]]
        invalid += [manifest(job("a", duration)) for duration in [True, 1.0, -1, 1_000_001, None]]
        invalid += [manifest({"id": "a", "duration": 0, "needs": needs})
                    for needs in [None, "a", [0], ["a"] * 129]]
        for value in invalid:
            with self.subTest(value=value):
                self.assertEqual(plan(value), {"error": "invalid-manifest"})

    def test_phase_precedence_independent_of_source_order(self):
        cases = [
            ([job("a"), job("a"), job("bad", True)], {"error": "invalid-manifest"}),
            ([job("a"), job("a"), job("b", needs=["x", "x"])],
             {"error": "duplicate-id", "ids": ["a"]}),
            ([job("a", needs=["a"]), job("b", needs=["x", "x"])],
             {"error": "duplicate-dependency", "jobs": ["b"]}),
            ([job("a", needs=["a"]), job("b", needs=["x"])],
             {"error": "unknown-dependency", "ids": ["x"]}),
        ]
        for jobs, expected in cases:
            for permutation in itertools.permutations(jobs):
                self.assertEqual(plan(manifest(*permutation)), expected)

    def test_errors_are_distinct_and_sorted(self):
        self.assertEqual(plan(manifest(job("z"), job("a"), job("z"), job("a"), job("z"))),
                         {"error": "duplicate-id", "ids": ["a", "z"]})
        self.assertEqual(plan(manifest(job("z", needs=["x", "x"]), job("a", needs=["y", "y"]))),
                         {"error": "duplicate-dependency", "jobs": ["a", "z"]})
        self.assertEqual(plan(manifest(job("z", needs=["y", "x"]), job("a", needs=["x"]))),
                         {"error": "unknown-dependency", "ids": ["x", "y"]})

    def test_cycle_includes_downstream_but_not_removable_ancestors(self):
        result = plan(manifest(job("root"), job("a", needs=["b", "root"]),
                               job("b", needs=["a"]), job("tail", needs=["b"])))
        self.assertEqual(result, {"error": "cycle", "blocked": ["a", "b", "tail"]})
        self.assertEqual(plan(manifest(job("a", needs=["a"]))), {"error": "cycle", "blocked": ["a"]})


class PlanningTests(unittest.TestCase):
    def test_contract_example_and_permutation_invariance(self):
        expected = {"order": ["b", "a", "z"], "layers": [["b", "z"], ["a"]],
                    "timings": [{"id": "a", "start": 2, "finish": 5},
                                {"id": "b", "start": 0, "finish": 2},
                                {"id": "z", "start": 0, "finish": 5}], "makespan": 5}
        for jobs in itertools.permutations([job("z", 5), job("b", 2), job("a", 3, ["b"])]):
            self.assertEqual(plan(manifest(*jobs)), expected)

    def test_empty_graph(self):
        self.assertEqual(plan(manifest()), {"order": [], "layers": [], "timings": [], "makespan": 0})

    def test_join_uses_slowest_parent_and_zero_duration(self):
        jobs = [job("a", 5), job("b", 0), job("c", 7, ["b"]), job("d", 0, ["a", "c"])]
        result = plan(manifest(*jobs))
        self.assertEqual(result["layers"], [["a", "b"], ["c"], ["d"]])
        self.assertEqual(result["timings"][-1], {"id": "d", "start": 7, "finish": 7})
        self.assertEqual(result["makespan"], 7)
        jobs[-1]["needs"].reverse()
        self.assertEqual(plan(manifest(*reversed(jobs))), result)

    def test_maximum_chain(self):
        jobs = [job(f"j{i:03d}", 1_000_000, [f"j{i-1:03d}"] if i else []) for i in range(128)]
        result = plan(manifest(*reversed(jobs)))
        self.assertEqual(result["makespan"], 128_000_000)
        self.assertEqual(result["layers"], [[j["id"]] for j in jobs])
        self.assertEqual(result["order"], [j["id"] for j in jobs])


if __name__ == "__main__":
    unittest.main()
