import copy
import itertools
import json
import subprocess
import sys
import unittest
from pathlib import Path

import main


def board(roles=('passive', 'passive', 'passive')):
    return dict(version=1, unit='um', width=100, height=100, clearance=0,
                components=[dict(id=name, x=i*10, y=0, width=2, height=2,
                                 pins=['p'], pin_roles=[dict(pin='p', role=role)])
                            for i, (name, role) in enumerate(zip(('a', 'b', 'c'), roles))],
                nets=[dict(id='n', members=[dict(component=name, pin='p')
                                          for name in ('a', 'b', 'c')])])


class Roles(unittest.TestCase):
    def test_all_role_combinations(self):
        for roles in itertools.product(('passive', 'input', 'output'), repeat=3):
            with self.subTest(roles=roles):
                result = main.inspect_board(board(roles))
                expected = []
                if sum(role == 'output' for role in roles) >= 2:
                    expected.append(dict(code='multiple-drivers', subjects=['n']))
                if 'input' in roles and 'output' not in roles:
                    expected.append(dict(code='undriven-input-net', subjects=['n']))
                self.assertEqual(result['findings'], expected)
                self.assertEqual(result['nets'][0]['span'], 20)

    def test_default_and_empty_roles(self):
        explicit = board()
        omitted = copy.deepcopy(explicit)
        empty = copy.deepcopy(explicit)
        for component in omitted['components']:
            component.pop('pin_roles')
        for component in empty['components']:
            component['pin_roles'] = []
        self.assertEqual(main.inspect_board(explicit), main.inspect_board(omitted))
        self.assertEqual(main.inspect_board(explicit), main.inspect_board(empty))

    def test_invalid_schema_precedes_duplicates(self):
        invalid = [None, {}, 'input', 0, [None], [dict(pin='missing', role='input')],
                   [dict(pin='p', role='other')], [dict(pin='p', role=True)],
                   [dict(pin=[], role='input')], [dict(pin='p', role=[])],
                   [dict(pin='p')], [dict(pin='p', role='input', extra=0)],
                   [dict(pin='p', role='input')]*2,
                   [dict(pin='p', role='passive')]*33]
        for value in invalid:
            with self.subTest(value=value):
                item = board()
                item['components'][0]['pin_roles'] = value
                item['components'][1]['id'] = 'a'
                self.assertEqual(main.inspect_board(item), {'error': 'invalid-board'})

    def test_unknown_and_reused_precede_design_findings(self):
        item = board(('output', 'output', 'input'))
        item['nets'][0]['members'].append(dict(component='a', pin='p'))
        self.assertEqual(main.inspect_board(item), dict(error='reused-pin', refs=[dict(component='a', pin='p')]))
        item['nets'][0]['members'].append(dict(component='missing', pin='p'))
        self.assertEqual(main.inspect_board(item), dict(error='unknown-pin', refs=[dict(component='missing', pin='p')]))

    def test_singleton_and_unconnected_input(self):
        item = board(('input', 'input', 'input'))
        item['nets'][0]['members'] = item['nets'][0]['members'][:1]
        self.assertEqual(main.inspect_board(item)['findings'], [
            dict(code='unconnected-pin', subjects=['b', 'p']),
            dict(code='unconnected-pin', subjects=['c', 'p']),
            dict(code='underconnected-net', subjects=['n']),
            dict(code='undriven-input-net', subjects=['n'])])

    def test_two_outputs_same_component(self):
        item = board()
        item['components'][0]['pins'] = ['p', 'q']
        item['components'][0]['pin_roles'] = [dict(pin=pin, role='output') for pin in ('p', 'q')]
        item['nets'][0]['members'].append(dict(component='a', pin='q'))
        self.assertEqual(main.inspect_board(item)['findings'], [dict(code='multiple-drivers', subjects=['n'])])

    def test_cli(self):
        result = subprocess.run([sys.executable, str(Path(main.__file__))],
                                input=json.dumps({'cases':[board(('output', 'input', 'passive'))]}).encode(),
                                capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout)['results'][0]['findings'], [])
        invalid = subprocess.run([sys.executable, str(Path(main.__file__))], input=b'{"cases":[],"cases":[]}',
                                 capture_output=True, check=True)
        self.assertEqual(json.loads(invalid.stdout), dict(error='invalid-request'))


if __name__ == '__main__':
    unittest.main()
