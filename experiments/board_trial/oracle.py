"""Independent interval/set oracle for the bounded board keepout contract."""
import argparse
from collections import Counter
import json
from pathlib import Path

LIMIT = 1_000_000_000
CAPACITIES = {'components': 4, 'nets': 4, 'regions': 4, 'features': 8}
FAMILIES = frozenset(('component', 'track', 'via'))


def exact_keys(value, names):
    if not isinstance(value, dict) or set(value) != set(names):
        raise ValueError('invalid object fields')


def integers(values):
    return isinstance(values, list) and all(type(value) is int for value in values)


def shape(document):
    """Check transport shape without hiding logical errors from the guest model."""
    exact_keys(document, ('version', 'board'))
    if type(document['version']) is not int or document['version'] != 1:
        raise ValueError('unsupported snapshot version')
    board = document['board']
    exact_keys(board, ('outline', *CAPACITIES))
    for name, capacity in CAPACITIES.items():
        if not isinstance(board[name], list) or len(board[name]) > capacity:
            raise ValueError('snapshot capacity exceeded')
    for name in ('components', 'nets'):
        if not integers(board[name]):
            raise ValueError('IDs must be integers')
    rectangles = [board['outline']]
    for region in board['regions']:
        exact_keys(region, ('rect', 'face', 'blocks', 'allow_nets'))
        if region['face'] not in ('top', 'bottom', 'both'):
            raise ValueError('invalid region face')
        if not isinstance(region['blocks'], list) or not all(isinstance(b, str) and b in FAMILIES for b in region['blocks']):
            raise ValueError('invalid region blocks')
        if not integers(region['allow_nets']) or len(region['allow_nets']) > 4:
            raise ValueError('invalid allowed nets')
        rectangles.append(region['rect'])
    for feature in board['features']:
        if not isinstance(feature, dict) or not isinstance(feature.get('kind'), str) or feature['kind'] not in FAMILIES:
            raise ValueError('invalid feature kind')
        kind = feature['kind']
        fields = {'component': ('id', 'face'), 'track': ('net', 'layer'), 'via': ('net',)}[kind]
        exact_keys(feature, ('kind', 'rect', *fields))
        if type(feature['id' if kind == 'component' else 'net']) is not int:
            raise ValueError('feature identity must be an integer')
        if kind == 'component' and feature['face'] not in ('top', 'bottom'):
            raise ValueError('invalid component face')
        if kind == 'track' and feature['layer'] not in ('front', 'back', 'inner'):
            raise ValueError('invalid track layer')
        rectangles.append(feature['rect'])
    if any(not integers(rect) or len(rect) != 4 for rect in rectangles):
        raise ValueError('rectangle requires four integers')
    for value in (*board['components'], *board['nets']):
        if not 0 <= value < 2**64:
            raise ValueError('catalog identity exceeds u64')
    for region in board['regions']:
        if any(not 0 <= n < 2**64 for n in region['allow_nets']):
            raise ValueError('allowed net exceeds u64')
    for feature in board['features']:
        identity = feature['id' if feature['kind'] == 'component' else 'net']
        if not 0 <= identity < 2**64:
            raise ValueError('feature identity exceeds u64')
    if any(not -(2**63) <= n < 2**63 for rect in rectangles for n in rect):
        raise ValueError('coordinate exceeds i64')
    return board


def valid_rect(rect):
    x, y, width, height = rect
    return (all(-LIMIT <= v <= LIMIT for v in (x, y, x + width, y + height))
            and 1 <= width <= LIMIT and 1 <= height <= LIMIT)


def input_problem(board):
    if not valid_rect(board['outline']):
        return 'invalid_bounds'
    for name, duplicate in (('components', 'duplicate_component'), ('nets', 'duplicate_net')):
        seen = set()
        for identity in board[name]:
            if identity == 0:
                return 'invalid_id'
            if identity in seen:
                return duplicate
            seen.add(identity)
    nets = set(board['nets'])
    for region in board['regions']:
        if not valid_rect(region['rect']):
            return 'invalid_bounds'
        if not region['blocks']:
            return 'empty_blocks'
        if any(n not in nets for n in region['allow_nets']):
            return 'unknown_allow_net'
    for feature in board['features']:
        if not valid_rect(feature['rect']):
            return 'invalid_bounds'
        if feature['kind'] == 'component':
            if feature['id'] not in board['components']:
                return 'missing_component'
        elif feature['net'] not in nets:
            return 'missing_net'
    return None


def intervals(rect):
    return ((rect[0], rect[0] + rect[2]), (rect[1], rect[1] + rect[3]))


def applies(feature, region):
    kind = feature['kind']
    if kind not in region['blocks']:
        return False
    if kind != 'component' and feature['net'] in region['allow_nets']:
        return False
    faces = {'top', 'bottom'} if region['face'] == 'both' else {region['face']}
    occupied = ({feature['face']} if kind == 'component' else
                {'front': {'top'}, 'back': {'bottom'}, 'inner': set()}[feature['layer']]
                if kind == 'track' else {'top', 'bottom'})
    return region['face'] == 'both' or bool(faces & occupied)


def evaluate(document, unavailable=False):
    board = shape(document)
    problem = input_problem(board)
    if problem:
        return {'err': {'input': problem}, 'calls': 0}
    outline = intervals(board['outline'])
    violations = []
    calls = 0
    for index, feature in enumerate(board['features']):
        footprint = intervals(feature['rect'])
        if any(a < lo or b > hi for (a, b), (lo, hi) in zip(footprint, outline)):
            violations.append({'feature': index, 'kind': 'outside_board', 'region': None})
        for region_index, region in enumerate(board['regions']):
            if not applies(feature, region):
                continue
            calls += 1
            if unavailable:
                return {'err': {'geometry': 'unavailable'}, 'calls': calls}
            if all(max(a, lo) < min(b, hi) for (a, b), (lo, hi) in zip(footprint, intervals(region['rect']))):
                violations.append({'feature': index, 'kind': 'keepout', 'region': region_index})
    return {'ok': {'violations': len(violations), 'first': violations[0] if violations else None}, 'calls': calls}


def check(path):
    cases = json.loads(path.read_text())
    names = set()
    outcomes = Counter()
    for case in cases:
        exact_keys(case, ('name', 'input', 'unavailable', 'expected'))
        assert case['name'] not in names, case['name']
        assert type(case['unavailable']) is bool, case['name']
        names.add(case['name'])
        actual = evaluate(case['input'], case['unavailable'])
        assert actual == case['expected'], (case['name'], case['expected'], actual)
        outcomes['ok' if 'ok' in actual else next(iter(actual['err'].values()))] += 1
    assert names, 'empty oracle corpus'
    print(f'Board contract oracle: {len(names)} fixed cases; {dict(sorted(outcomes.items()))}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', type=Path, default=Path(__file__).with_name('cases.json'))
    check(parser.parse_args().check)
