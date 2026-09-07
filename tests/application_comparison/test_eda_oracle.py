from copy import deepcopy
import itertools
import json
import random
import unittest
import xml.etree.ElementTree as ET
from experiments.application_comparison.eda_oracle import board_result, response, response_bytes, generated_cases


def component(name, x=0, y=0, width=1, height=1, pins=()):
    return dict(id=name, x=x, y=y, width=width, height=height, pins=list(pins))


def board(components=(), nets=(), clearance=0, unit='um'):
    return dict(version=1, unit=unit, width=100, height=100, clearance=clearance,
                components=list(components), nets=list(nets))


def member(name, pin='p'):
    return dict(component=name, pin=pin)


class EdaOracleTests(unittest.TestCase):
    def test_transport_generation_and_order_invariance(self):
        request = generated_cases('public-eda-oracle-v1', 64)
        original = response(request)
        self.assertEqual(request, generated_cases('public-eda-oracle-v1', 64))
        self.assertNotEqual(request, generated_cases('public-eda-oracle-v2', 64))
        self.assertEqual(response_bytes(json.dumps(request).encode()), original)
        self.assertEqual({item.get('error', 'success') for item in original['results']},
                         {'success', 'invalid-board', 'duplicate-id', 'unknown-pin', 'reused-pin'})
        rng = random.Random(77)
        for value in request['cases']:
            rng.shuffle(value['components'])
            rng.shuffle(value['nets'])
            for net in value['nets']:
                rng.shuffle(net['members'])
        self.assertEqual(response(request), original)
        for raw in [b'{"cases":[],"cases":[]}', b'\xff', b'{"cases":[NaN]}',
                    b'{"cases":[9223372036854775808]}', b' ' * (1024 * 1024 + 1)]:
            self.assertEqual(response_bytes(raw), {'error': 'invalid-request'})

    def test_schema_and_reference_validation_precedence(self):
        a = component('a', pins=['p'])
        self.assertEqual(board_result(board([a, dict(a, width=True)])), {'error': 'invalid-board'})
        self.assertEqual(board_result(board([a, a], [dict(id='n', members=[member('missing')])])),
                         {'error': 'duplicate-id', 'components': ['a'], 'nets': []})
        self.assertEqual(board_result(board([a], [dict(id='n', members=[member('missing')] * 2)])),
                         {'error': 'unknown-pin', 'refs': [member('missing')]})
        self.assertEqual(board_result(board([a], [dict(id='n', members=[member('a')] * 2)])),
                         {'error': 'reused-pin', 'refs': [member('a')]})
        self.assertEqual(board_result(board([component('a', pins=['p', 'p'])])), {'error': 'invalid-board'})
        self.assertEqual(response({'cases': [None]}), {'results': [{'error': 'invalid-board'}]})
        self.assertEqual(response({}), {'error': 'invalid-request'})

    def test_geometry_against_discrete_point_and_cell_enumeration(self):
        # For integer rectangle vertices, a closest pair of closed-rectangle
        # points can be chosen on this integer lattice. Interior overlap is
        # independently witnessed by a shared unit cell. No interval-gap formula.
        fixed = component('a', 0, 0, 2, 2)
        points_a = set(itertools.product(range(3), repeat=2))
        cells_a = set(itertools.product(range(2), repeat=2))
        for x, y, w, h, clearance in itertools.product(range(-2, 5), range(-2, 5), (1, 2), (1, 2), range(4)):
            other = component('b', x, y, w, h)
            points_b = set(itertools.product(range(x, x+w+1), range(y, y+h+1)))
            cells_b = set(itertools.product(range(x, x+w), range(y, y+h)))
            distance = min((ax-bx)**2 + (ay-by)**2 for ax, ay in points_a for bx, by in points_b)
            expected = bool(cells_a & cells_b) or distance < clearance**2
            result = board_result(board([other, fixed], clearance=clearance))
            actual = any(item['code'] == 'clearance' for item in result['findings'])
            self.assertEqual(actual, expected, (x, y, w, h, clearance))

    def test_unit_equivalence_and_half_unit_span_rounding(self):
        value = board([component('a', 0, 0, 1, 1, ['p']), component('b', 3, 0, 2, 1, ['p'])],
                      [dict(id='n', members=[member('b'), member('a')])])
        result = board_result(value)
        self.assertEqual(result['nets'], [dict(id='n', members=[member('a'), member('b')], span=4)])
        value['unit'] = 'mm'
        scaled = deepcopy(value)
        scaled['unit'] = 'um'
        for key in ('width', 'height', 'clearance'):
            scaled[key] *= 1000
        for item in scaled['components']:
            for key in ('x', 'y', 'width', 'height'):
                item[key] *= 1000
        self.assertEqual(board_result(value), board_result(scaled))
        self.assertEqual(board_result(value)['nets'][0]['span'], 3500)

    def test_svg_report_order_boundaries_and_large_arithmetic(self):
        value = board([component('z', 99, 99), component('a', -1, pins=['p'])],
                      [dict(id='n', members=[])])
        result = board_result(value)
        self.assertEqual(result['findings'], [dict(code='outside-board', subjects=['a']),
            dict(code='unconnected-pin', subjects=['a', 'p']), dict(code='underconnected-net', subjects=['n'])])
        document = ET.fromstring(result['svg'])
        self.assertEqual(document.attrib['viewBox'], '0 0 100 100')
        self.assertEqual([item.attrib.get('id') for item in document], [None, 'a', 'z'])
        value['components'].reverse()
        self.assertEqual(board_result(value), result)
        far = board([component('a', -1000000, -1000000), component('b', 1000000, 1000000)],
                    clearance=1000000, unit='mm')
        self.assertFalse(any(item['code'] == 'clearance' for item in board_result(far)['findings']))
        self.assertEqual(board_result(board())['svg'], '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="0" y="0" width="100" height="100" fill="white" stroke="black"/></svg>')


if __name__ == '__main__':
    unittest.main()
