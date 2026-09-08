#!/usr/bin/env python3
"""Application schema checks across the ordinary JSON view boundary."""
import copy
from test_cli import board, component, invoke


def tests():
    invalid = []
    for field in ('version', 'unit', 'width', 'height', 'clearance', 'components', 'nets'):
        missing = board()
        del missing[field]
        invalid.append(missing)
        invalid.append(board(**{field: None}))
    for field in ('version', 'width', 'height', 'clearance'):
        invalid.extend(board(**{field: value}) for value in (True, 1.0))
    unknown = board()
    del unknown['unit']
    unknown['unknown'] = 'um'
    invalid.append(unknown)  # Same object size is not sufficient schema validation.
    invalid.extend([
        board(components=[component('a', pins=[[]])]),
        board(components=[component('a', pins=['p', 'p'])]),
        board(components=[component('a', pins=['p'])], nets=[{'id': 'n', 'members': [[]]}]),
        board(components=[component('a')]*129),
        board(components=[component('a', pins=['p'+str(i) for i in range(33)])]),
    ])
    assert invoke({'cases': invalid}) == {'results': [{'error': 'invalid-board'}]*len(invalid)}
    # A later schema failure must still precede duplicated component IDs.
    invalid_late = board(components=[component('a'), component('a')],
                         nets=[{'id': 'n', 'members': [{'component': 'a', 'pin': None}]}])
    assert invoke({'cases': [invalid_late]}) == {'results': [{'error': 'invalid-board'}]}
    # Independent containers and a trailing member challenge subtree-skipping cursors.
    valid = board(components=[component('a', pins=['x', 'y']), component('b', x=20, pins=['z'])],
                  nets=[{'id': 'empty', 'members': []},
                        {'id': 'wired', 'members': [{'component': 'a', 'pin': 'x'},
                                                     {'component': 'b', 'pin': 'z'}]}])
    variant = copy.deepcopy(valid)
    variant['components'].reverse()
    variant['nets'].reverse()
    variant['nets'][0]['members'].reverse()
    assert invoke({'cases': [valid]}) == invoke({'cases': [variant]})
    assert invoke(b'{"cases":[{"version":1,"unit":"um","width":100,"height":100,"clearance":0,"components":[{"id":"a","x":0,"y":0,"width":1,"height":1,"pins":["p","\\u0070"]}],"nets":[]}]}') == {'results': [{'error': 'invalid-board'}]}
    print('schema boundary and subtree traversal cases passed')


if __name__ == '__main__':
    tests()
