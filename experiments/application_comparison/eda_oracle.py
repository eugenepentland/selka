"""Coordinator-only EDA contract oracle. No native geometry or application imports."""
from collections import Counter
import random
from .oracle_transport import respond
from .planner_oracle import identifier


def integer(value, minimum, maximum):
    return type(value) is int and minimum <= value <= maximum


def schema(board):
    if (not isinstance(board, dict) or set(board) != {
            'version', 'unit', 'width', 'height', 'clearance', 'components', 'nets'} or
            type(board['version']) is not int or board['version'] != 1 or
            board['unit'] not in ('um', 'mm') or
            not all(integer(board[key], 1, 1000000) for key in ('width', 'height')) or
            not integer(board['clearance'], 0, 1000000) or
            not isinstance(board['components'], list) or len(board['components']) > 128 or
            not isinstance(board['nets'], list) or len(board['nets']) > 128):
        return False
    for component in board['components']:
        if (not isinstance(component, dict) or set(component) != {'id', 'x', 'y', 'width', 'height', 'pins'} or
                not identifier(component['id']) or
                not all(integer(component[key], -1000000, 1000000) for key in ('x', 'y')) or
                not all(integer(component[key], 1, 1000000) for key in ('width', 'height')) or
                not isinstance(component['pins'], list) or len(component['pins']) > 32 or
                not all(identifier(pin) for pin in component['pins']) or
                len(set(component['pins'])) != len(component['pins'])):
            return False
    for net in board['nets']:
        if (not isinstance(net, dict) or set(net) != {'id', 'members'} or not identifier(net['id']) or
                not isinstance(net['members'], list) or len(net['members']) > 128):
            return False
        for ref in net['members']:
            if (not isinstance(ref, dict) or set(ref) != {'component', 'pin'} or
                    not identifier(ref['component']) or not identifier(ref['pin'])):
                return False
    return True


def refs(items):
    return [{'component': component, 'pin': pin} for component, pin in sorted(items)]


def board_result(board):
    if not schema(board):
        return {'error': 'invalid-board'}
    repeated = {key: sorted(name for name, count in Counter(item['id'] for item in board[key]).items() if count > 1)
                for key in ('components', 'nets')}
    if any(repeated.values()):
        return dict(error='duplicate-id', **repeated)
    declared = {(component['id'], pin) for component in board['components'] for pin in component['pins']}
    used = Counter((ref['component'], ref['pin']) for net in board['nets'] for ref in net['members'])
    unknown = set(used) - declared
    if unknown:
        return {'error': 'unknown-pin', 'refs': refs(unknown)}
    reused = {ref for ref, count in used.items() if count > 1}
    if reused:
        return {'error': 'reused-pin', 'refs': refs(reused)}
    scale = 1000 if board['unit'] == 'mm' else 1
    width, height, clearance = (board[key] * scale for key in ('width', 'height', 'clearance'))
    components = sorted(board['components'], key=lambda item: item['id'])
    rectangles = {item['id']: tuple(item[key] * scale for key in ('x', 'y', 'width', 'height')) for item in components}
    findings = []
    def finding(code, subjects):
        findings.append({'code': code, 'subjects': subjects})
    for index, component in enumerate(components):
        name = component['id']
        x, y, w, h = rectangles[name]
        if x < 0 or y < 0 or x + w > width or y + h > height:
            finding('outside-board', [name])
        for other in components[index + 1:]:
            ox, oy, ow, oh = rectangles[other['id']]
            gap_x, gap_y = max(0, x - ox - ow, ox - x - w), max(0, y - oy - oh, oy - y - h)
            overlap = max(x, ox) < min(x + w, ox + ow) and max(y, oy) < min(y + h, oy + oh)
            if overlap or gap_x * gap_x + gap_y * gap_y < clearance * clearance:
                finding('clearance', [name, other['id']])
    for ref in sorted(declared - set(used)):
        finding('unconnected-pin', list(ref))
    nets = []
    for net in sorted(board['nets'], key=lambda item: item['id']):
        members = {(ref['component'], ref['pin']) for ref in net['members']}
        if len(members) < 2:
            finding('underconnected-net', [net['id']])
        centers = [(2 * rectangles[name][0] + rectangles[name][2],
                    2 * rectangles[name][1] + rectangles[name][3]) for name, _ in members]
        extent = sum(max(axis) - min(axis) for axis in zip(*centers)) if centers else 0
        nets.append({'id': net['id'], 'members': refs(members), 'span': (extent + 1) // 2})
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">'
    svg += f'<rect x="0" y="0" width="{width}" height="{height}" fill="white" stroke="black"/>'
    for name, (x, y, w, h) in rectangles.items():
        svg += f'<rect id="{name}" x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="black"/>'
    svg += '</svg>'
    return {'unit': 'um', 'findings': sorted(findings, key=lambda item: (item['code'], item['subjects'])),
            'nets': nets, 'svg': svg}


def response(request):
    if (not isinstance(request, dict) or set(request) != {'cases'} or
            not isinstance(request['cases'], list) or len(request['cases']) > 64):
        return {'error': 'invalid-request'}
    return {'results': [board_result(board) for board in request['cases']]}


def response_bytes(raw):
    return respond(raw, response)


def generated_cases(seed, count=32):
    """Reproducible construction cases; scoring requires a separate frozen seed."""
    if type(count) is not int or not 0 <= count <= 64:
        raise ValueError('case count must be 0..64')
    rng = random.Random(seed)
    cases = []
    for index in range(count):
        components = [dict(id=f'c{i:03}', x=rng.randrange(-20, 100), y=rng.randrange(-20, 100),
                           width=rng.randrange(1, 20), height=rng.randrange(1, 20), pins=['p', 'q'])
                      for i in range(rng.randrange(2, 16))]
        available = [{'component': item['id'], 'pin': pin} for item in components for pin in item['pins']]
        rng.shuffle(available)
        nets = [dict(id='n000', members=available[:len(available)//2]),
                dict(id='n001', members=available[len(available)//2:-1])]
        value = dict(version=1, unit=rng.choice(['um', 'mm']), width=100, height=100,
                     clearance=rng.choice([0, 1, 5, 100]), components=components, nets=nets)
        mode = index % 8
        if mode == 1:
            components[0]['width'] = False
        elif mode == 2:
            components.append(dict(components[0]))
        elif mode == 3:
            nets[0]['members'].append({'component': 'absent', 'pin': 'p'})
        elif mode == 4:
            nets[1]['members'].append(dict(nets[0]['members'][0]))
        elif mode == 5:
            nets.append(dict(id='empty', members=[]))
        elif mode == 6:
            value['components'], value['nets'] = [], []
        rng.shuffle(components)
        rng.shuffle(nets)
        cases.append(value)
    return {'cases': cases}
