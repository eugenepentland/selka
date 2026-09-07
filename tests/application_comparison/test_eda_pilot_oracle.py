import copy
import itertools
import unittest
import xml.etree.ElementTree as ET
from experiments.application_comparison import eda_oracle as base
from experiments.application_comparison import eda_pilot_oracle as pilot


def board():
    return dict(version=1, unit='um', width=10, height=10, clearance=1,
                components=[dict(id='a', x=0, y=0, width=3, height=1, pins=['p', 'q']),
                            dict(id='b', x=4, y=2, width=1, height=3, pins=['p'])],
                nets=[dict(id='n', members=[dict(component='a', pin='p'), dict(component='b', pin='p')])])


class EdaPilotTests(unittest.TestCase):
    def test_original_inputs_preserved_and_extension_tasks_separate(self):
        for value in base.generated_cases('public-pilot-oracle-regression', 64)['cases']:
            before = copy.deepcopy(value)
            self.assertEqual(pilot.rotation_result(value), base.board_result(value))
            self.assertEqual(pilot.pin_roles_result(value), base.board_result(value))
            self.assertEqual(value, before)
        value = board()
        value['components'][0]['rotation'] = 0
        self.assertEqual(pilot.pin_roles_result(value), {'error': 'invalid-board'})
        value = board()
        value['components'][0]['pin_roles'] = []
        self.assertEqual(pilot.rotation_result(value), {'error': 'invalid-board'})

    def test_roles_exhaustive_combinations_with_unconnected_input(self):
        for left, right in itertools.product(('passive', 'input', 'output'), repeat=2):
            value = board()
            expected = base.board_result(value)
            value['components'][0]['pin_roles'] = [dict(pin='p', role=left), dict(pin='q', role='input')]
            value['components'][1]['pin_roles'] = [dict(pin='p', role=right)]
            extra = []
            if left == right == 'output':
                extra.append(dict(code='multiple-drivers', subjects=['n']))
            if (left == 'input' or right == 'input') and left != 'output' and right != 'output':
                extra.append(dict(code='undriven-input-net', subjects=['n']))
            expected['findings'] = sorted(expected['findings'] + extra, key=lambda item: (item['code'], item['subjects']))
            before = copy.deepcopy(value)
            self.assertEqual(pilot.pin_roles_result(value), expected)
            self.assertEqual(value, before)

    def test_roles_schema_and_reference_precedence(self):
        invalid = [None, {}, [None], [dict(pin='p', role=[])], [dict(pin='p', role='driver')],
                   [dict(pin='absent', role='input')], [dict(pin='p', role='input', extra=0)],
                   [dict(pin='p', role='input')] * 2, [dict(pin=[], role='input')],
                   [dict(pin='p', role='input')] * 33]
        for assignments in invalid:
            with self.subTest(assignments=assignments):
                value = board()
                value['components'][0]['pin_roles'] = assignments
                value['nets'][0]['members'].append(dict(component='absent', pin='p'))
                self.assertEqual(pilot.pin_roles_result(value), {'error': 'invalid-board'})
        value = board()
        value['components'][0]['pin_roles'] = [dict(pin='p', role='input')]
        value['nets'][0]['members'].append(dict(component='absent', pin='p'))
        self.assertEqual(pilot.pin_roles_result(value), {'error': 'unknown-pin', 'refs': [dict(component='absent', pin='p')]})
        value['nets'][0]['members'][-1] = dict(component='a', pin='p')
        self.assertEqual(pilot.pin_roles_result(value), {'error': 'reused-pin', 'refs': [dict(component='a', pin='p')]})

    def test_rotation_geometry_and_svg_against_explicit_occupied_boxes(self):
        for angle_a, angle_b, unit in itertools.product((0, 90, 180, 270), (0, 90, 180, 270), ('um', 'mm')):
            value = board()
            value['unit'] = unit
            value['components'][0]['rotation'] = angle_a
            value['components'][1]['rotation'] = angle_b
            # Explicit expected boxes, independently from the oracle's transform.
            a_box = (0, 0, 3, 1) if angle_a in (0, 180) else (0, 0, 1, 3)
            b_box = (4, 2, 1, 3) if angle_b in (0, 180) else (4, 2, 3, 1)
            scale = 1000 if unit == 'mm' else 1
            actual = pilot.rotation_result(value)
            rectangles = list(ET.fromstring(actual['svg']))[1:]
            for element, expected in zip(rectangles, (a_box, b_box)):
                self.assertEqual(tuple(int(element.attrib[key]) for key in ('x', 'y', 'width', 'height')),
                                 tuple(number * scale for number in expected))
                self.assertNotIn('transform', element.attrib)
            ax, ay, aw, ah = a_box
            bx, by, bw, bh = b_box
            doubled_span = abs((2*ax+aw)-(2*bx+bw)) + abs((2*ay+ah)-(2*by+bh))
            self.assertEqual(actual['nets'][0]['span'], (doubled_span * scale + 1) // 2)
            self.assertEqual(actual['findings'], [dict(code='unconnected-pin', subjects=['a', 'q'])])

    def test_rotation_changes_clearance_and_board_edge(self):
        value = board()
        value['components'][1].update(x=3, y=0)
        self.assertIn(dict(code='clearance', subjects=['a', 'b']), pilot.rotation_result(value)['findings'])
        value['components'][0]['rotation'] = 90
        self.assertNotIn(dict(code='clearance', subjects=['a', 'b']), pilot.rotation_result(value)['findings'])
        value['components'][0].update(x=9, y=0)
        self.assertNotIn(dict(code='outside-board', subjects=['a']), pilot.rotation_result(value)['findings'])
        value['components'][0]['rotation'] = 180
        self.assertIn(dict(code='outside-board', subjects=['a']), pilot.rotation_result(value)['findings'])
        for rotation in (True, 90.0, None, '90', -90, 360, []):
            value['components'][0]['rotation'] = rotation
            self.assertEqual(pilot.rotation_result(value), {'error': 'invalid-board'})

    def test_transport_and_clearance_equality(self):
        for task in pilot.HANDLERS:
            self.assertEqual(pilot.response_bytes(b'{"cases":[],"cases":[]}', task), {'error': 'invalid-request'})
        value = board()
        value['components'][1].update(x=4, y=0)
        result = pilot.response({'cases': [value]}, 'eda-clearance-boundary')['results'][0]
        self.assertNotIn(dict(code='clearance', subjects=['a', 'b']), result['findings'])


if __name__ == '__main__':
    unittest.main()
