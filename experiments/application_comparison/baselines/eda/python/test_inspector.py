import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

from inspector import INPUT_LIMIT, handle_request, inspect_board


def component(name='a', x=0, y=0, width=2, height=2, pins=None):
    return dict(id=name, x=x, y=y, width=width, height=height, pins=['p'] if pins is None else pins)


def member(name, pin='p'):
    return dict(component=name, pin=pin)


def board(components=None, nets=None, **changes):
    value = dict(version=1, unit='um', width=100, height=100, clearance=0,
                 components=[] if components is None else components, nets=[] if nets is None else nets)
    value.update(changes)
    return value


class TransportTests(unittest.TestCase):
    def test_empty_batch(self):
        self.assertEqual(handle_request(b'{"cases":[]}'), {'results': []})

    def test_invalid_transport(self):
        samples = [b'', b'{}', b'[]', b'{"cases":[],"extra":0}', b'{"cases":null}',
                   b'{"cases":[],"cases":[]}', b'{"cases":[{"x":0,"x":1}]}',
                   b'{"cases":[NaN]}', b'{"cases":[Infinity]}', b'{"cases":[1e400]}',
                   b'{"cases":[9223372036854775808]}', b'{"cases":[-9223372036854775809]}',
                   b'{"cases":["\xff"]}', b'{"cases":[]} trailing',
                   json.dumps({'cases': [None] * 65}).encode(), b' ' * (INPUT_LIMIT + 1)]
        for raw in samples:
            with self.subTest(raw=raw[:100]):
                self.assertEqual(handle_request(raw), {'error': 'invalid-request'})

    def test_signed_limits_and_independent_cases(self):
        self.assertEqual(handle_request(b'{"cases":[-9223372036854775808,9223372036854775807]}'),
                         {'results': [{'error': 'invalid-board'}] * 2})
        result = handle_request(json.dumps({'cases': [None, board()]}).encode())
        self.assertEqual(result['results'][0], {'error': 'invalid-board'})
        self.assertEqual(result['results'][1]['findings'], [])

    def test_byte_limit_inclusive(self):
        raw = b'{"cases":[]}'
        self.assertEqual(handle_request(raw + b' ' * (INPUT_LIMIT - len(raw))), {'results': []})

    def test_container_depth_boundary(self):
        # Root and cases array occupy two of the 64 permitted levels.
        for mixed in (False, True):
            for depth in (63, 64, 65):
                nested = '0'
                for level in range(depth - 2):
                    nested = '{"x":' + nested + '}' if mixed and level % 2 else '[' + nested + ']'
                raw = ('{"cases":[' + nested + ']}').encode()
                expected = {'error': 'invalid-request'} if depth > 64 else {'results': [{'error': 'invalid-board'}]}
                with self.subTest(depth=depth, mixed=mixed):
                    self.assertEqual(handle_request(raw), expected)

    def test_depth_ignores_string_delimiters_and_escapes(self):
        for content in ('[' * 100, '}' * 100, '\\"[{]}' * 100, '\\' * 100):
            raw = json.dumps({'cases': [content]}).encode()
            self.assertEqual(handle_request(raw), {'results': [{'error': 'invalid-board'}]})
        # Escaped strings before a genuinely deep container must not hide it.
        raw = ('{"cases":["escaped \\\" quote",' + '[' * 63 + '0' + ']' * 63 + ']}').encode()
        self.assertEqual(handle_request(raw), {'error': 'invalid-request'})

    def test_depth_failure_suppresses_all_results(self):
        raw = ('{"cases":[' + json.dumps(board()) + ',' + '[' * 63 + '0' + ']' * 63 + ']}').encode()
        self.assertEqual(handle_request(raw), {'error': 'invalid-request'})

    def test_unpaired_surrogates_reject_entire_request(self):
        for escaped in (r'\ud800', r'\udfff', r'\udc00\ud800', r'\ud800x',
                        r'\ud800\ud800', r'\ud800\udc00\ud800'):
            for raw in (
                '{"cases":["' + escaped + '"]}',
                '{"cases":[{"' + escaped + '":0}]}',
                '{"cases":[' + json.dumps(board()) + ',{"extra":["' + escaped + '"]}]}',
            ):
                with self.subTest(raw=raw):
                    self.assertEqual(handle_request(raw.encode()), {'error': 'invalid-request'})

    def test_valid_surrogate_pairs_reach_schema_validation(self):
        for content in (r'\ud800\udc00', r'\udbff\udfff', '😀', r'\ud83d\ude00'):
            for raw in ('{"cases":["' + content + '"]}', '{"cases":[{"' + content + '":0}]}'):
                self.assertEqual(handle_request(raw.encode()), {'results': [{'error': 'invalid-board'}]})
        # A literal backslash followed by uD800 is ordinary scalar text.
        raw = json.dumps({'cases': [r'\ud800']}).encode()
        self.assertEqual(handle_request(raw), {'results': [{'error': 'invalid-board'}]})

    def test_cli(self):
        script = Path(__file__).with_name('inspector.py')
        for raw, expected in [(b'{"cases":[]}', {'results': []}), (b'bad', {'error': 'invalid-request'})]:
            run = subprocess.run([sys.executable, '-B', str(script)], input=raw, capture_output=True)
            self.assertEqual(run.returncode, 0)
            self.assertEqual(json.loads(run.stdout), expected)
            self.assertEqual(run.stderr, b'')


class ValidationTests(unittest.TestCase):
    def test_schema_types_and_bounds(self):
        for key, values in {'version': [True, 1.0, 2], 'unit': ['UM', None, []],
                            'width': [0, 1000001, True], 'height': [-1, 2.0],
                            'clearance': [-1, 1000001], 'components': [None, [None] * 129],
                            'nets': [False, [None] * 129]}.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    candidate = board()
                    candidate[key] = value
                    self.assertEqual(inspect_board(candidate), {'error': 'invalid-board'})
        for name in ['A', '', 'a\n', 'a' * 33, 'é', 'a b']:
            self.assertEqual(inspect_board(board([component(name)])), {'error': 'invalid-board'})
        self.assertEqual(inspect_board(board([component(pins=['p', 'p'])])), {'error': 'invalid-board'})
        self.assertEqual(inspect_board(board([component(pins=[[]])])), {'error': 'invalid-board'})
        for value in [board(extra=1), {k: v for k, v in board().items() if k != 'nets'}]:
            self.assertEqual(inspect_board(value), {'error': 'invalid-board'})

    def test_validation_phase_precedence(self):
        value = board([component('a'), component('a')], [{'id': 'n', 'members': [member('missing')]}])
        value['components'].append(component('z', pins=['p', 'p']))
        self.assertEqual(inspect_board(value), {'error': 'invalid-board'})
        value['components'].pop()
        self.assertEqual(inspect_board(value), {'error': 'duplicate-id', 'components': ['a'], 'nets': []})
        value['components'].pop()
        value['nets'][0]['members'] += [member('a'), member('a'), member('missing')]
        self.assertEqual(inspect_board(value), {'error': 'unknown-pin', 'refs': [member('missing')]})
        value['nets'][0]['members'] = [member('a'), member('a')]
        self.assertEqual(inspect_board(value), {'error': 'reused-pin', 'refs': [member('a')]})

    def test_duplicate_namespaces(self):
        value = board([component('z'), component('a'), component('z'), component('a')],
                      [{'id': 'n', 'members': []}] * 3)
        self.assertEqual(inspect_board(value), {'error': 'duplicate-id', 'components': ['a', 'z'], 'nets': ['n']})
        self.assertNotIn('error', inspect_board(board([component('a')], [{'id': 'a', 'members': []}])))

    def test_unknown_and_reused_sorting(self):
        value = board([component()], [{'id': 'n', 'members': [member('z'), member('a', 'z'), member('a', 'a'), member('z')]}])
        self.assertEqual(inspect_board(value), {'error': 'unknown-pin', 'refs': [member('a', 'a'), member('a', 'z'), member('z')]})
        value = board([component()], [{'id': 'a', 'members': [member('a')]}, {'id': 'b', 'members': [member('a')]}])
        self.assertEqual(inspect_board(value), {'error': 'reused-pin', 'refs': [member('a')]})


class GeometryTests(unittest.TestCase):
    def codes(self, value):
        return [(f['code'], f['subjects']) for f in inspect_board(value)['findings']]

    def test_clearance_euclidean_equality_overlap_and_touch(self):
        cases = [(2, 0, 0, False), (2, 2, 0, False), (1, 1, 0, True),
                 (5, 6, 5, False), (5, 6, 6, True), (2, 0, 1, True)]
        for x, y, clearance, violation in cases:
            with self.subTest(x=x, y=y, clearance=clearance):
                findings = self.codes(board([component('b', x, y, pins=[]), component('a', pins=[])], clearance=clearance))
                self.assertEqual(('clearance', ['a', 'b']) in findings, violation)

    def test_boundaries_and_findings_order(self):
        value = board([component('z', 99, 99), component('a', -1, 0), component('b', 98, 0)],
                      [{'id': 'empty', 'members': []}])
        self.assertEqual(self.codes(value), [('outside-board', ['a']), ('outside-board', ['z']),
                         ('unconnected-pin', ['a', 'p']), ('unconnected-pin', ['b', 'p']),
                         ('unconnected-pin', ['z', 'p']), ('underconnected-net', ['empty'])])

    def test_spans_round_up_and_repeated_centers(self):
        value = board([component('a', width=1, height=1, pins=['p', 'q']), component('b', 2, 0, width=2, height=1)],
                      [{'id': 'n', 'members': [member('b'), member('a', 'q'), member('a')]}])
        self.assertEqual(inspect_board(value)['nets'], [{'id': 'n', 'members': [member('a'), member('a', 'q'), member('b')], 'span': 3}])
        value['unit'] = 'mm'
        self.assertEqual(inspect_board(value)['nets'][0]['span'], 2500)

    def test_svg_exact_units_negative_coordinates(self):
        value = board([component('b', 1, 2, pins=[]), component('a', -1, 0, 1, 3, [])], unit='mm', width=5, height=6)
        self.assertEqual(inspect_board(value)['svg'], '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5000 6000"><rect x="0" y="0" width="5000" height="6000" fill="white" stroke="black"/><rect id="a" x="-1000" y="0" width="1000" height="3000" fill="none" stroke="black"/><rect id="b" x="1000" y="2000" width="2000" height="2000" fill="none" stroke="black"/></svg>')

    def test_permutation_invariance_and_nonmutation(self):
        value = board([component('b', 4, 0), component('a', pins=['q', 'p'])],
                      [{'id': 'z', 'members': []}, {'id': 'a', 'members': [member('b'), member('a')]}], clearance=3)
        original = copy.deepcopy(value)
        expected = inspect_board(value)
        self.assertEqual(value, original)
        value['components'].reverse()
        value['nets'].reverse()
        for c in value['components']:
            c['pins'].reverse()
        for n in value['nets']:
            n['members'].reverse()
        self.assertEqual(inspect_board(value), expected)

    def test_large_scaled_geometry(self):
        value = board([component('a', -1000000, -1000000, 1000000, 1000000, []),
                       component('b', 1000000, 1000000, 1000000, 1000000, [])], unit='mm',
                      width=1000000, height=1000000, clearance=1000000)
        self.assertEqual(self.codes(value), [('outside-board', ['a']), ('outside-board', ['b'])])


if __name__ == '__main__':
    unittest.main()
