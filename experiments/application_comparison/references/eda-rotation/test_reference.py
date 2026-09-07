import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

import main


def board():
    return dict(version=1, unit='um', width=20, height=20, clearance=2,
                components=[dict(id='a', x=0, y=0, width=3, height=7, pins=['p']),
                            dict(id='b', x=8, y=0, width=2, height=2, pins=['p'])],
                nets=[dict(id='n', members=[dict(component='a', pin='p'), dict(component='b', pin='p')])])


class Rotation(unittest.TestCase):
    def test_swap_changes_clearance_span_svg(self):
        item = board()
        initial = main.inspect_board(item)
        self.assertEqual(initial['findings'], [])
        self.assertEqual(initial['nets'][0]['span'], 10)
        item['components'][0]['rotation'] = 90
        rotated = main.inspect_board(item)
        self.assertEqual(rotated['findings'], [dict(code='clearance', subjects=['a','b'])])
        self.assertEqual(rotated['nets'][0]['span'], 6)
        self.assertEqual(rotated['svg'], '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect x="0" y="0" width="20" height="20" fill="white" stroke="black"/><rect id="a" x="0" y="0" width="7" height="3" fill="none" stroke="black"/><rect id="b" x="8" y="0" width="2" height="2" fill="none" stroke="black"/></svg>')

    def test_all_rotations_match_explicit_occupied_boxes(self):
        for angle in (0,90,180,270):
            for unit in ('um','mm'):
                for width, height in ((1,9),(7,2),(3,3)):
                    with self.subTest(angle=angle, unit=unit, size=(width,height)):
                        item = board()
                        item['unit'] = unit
                        item['components'][0].update(x=-1, y=18, width=width, height=height, rotation=angle)
                        expected = copy.deepcopy(item)
                        component = expected['components'][0]
                        del component['rotation']
                        if angle in (90,270):
                            component['width'], component['height'] = height, width
                        self.assertEqual(main.inspect_board(item), main.inspect_board(expected))

    def test_board_edge_and_top_left(self):
        item = board()
        item['components'] = [dict(id='a', x=13, y=17, width=3, height=7, rotation=270, pins=[])]
        item['nets'] = []
        self.assertEqual(main.inspect_board(item)['findings'], [])
        item['components'][0]['x'] += 1
        self.assertEqual(main.inspect_board(item)['findings'], [dict(code='outside-board', subjects=['a'])])
        item['components'][0]['rotation'] = 180
        self.assertEqual(main.inspect_board(item)['findings'], [dict(code='outside-board', subjects=['a'])])

    def test_schema_precedence(self):
        for value in (True,False,90.0,0.0,-90,360,45,'90',None,[],{}):
            with self.subTest(value=value):
                item=board()
                item['components'][0]['rotation']=value
                item['components'][1]['id']='a'
                self.assertEqual(main.inspect_board(item),dict(error='invalid-board'))
        for mutate in (lambda c:c.pop('width'), lambda c:c.update(pin_roles=[]), lambda c:c.update(extra=0)):
            item=board()
            mutate(item['components'][0])
            self.assertEqual(main.inspect_board(item),dict(error='invalid-board'))

    def test_cli_and_input_unchanged(self):
        item=board()
        item['components'][0]['rotation']=90
        saved=copy.deepcopy(item)
        expected=main.inspect_board(item)
        self.assertEqual(item,saved)
        output=subprocess.run([sys.executable,str(Path(main.__file__))],input=json.dumps(dict(cases=[item])).encode(),capture_output=True,check=True)
        self.assertEqual(json.loads(output.stdout),dict(results=[expected]))


if __name__ == '__main__':
    unittest.main()
