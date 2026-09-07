"""Coordinator reference for eda-rotation; standard-library EDA inspector."""
import json
import math
import re
import sys
from collections import Counter
from itertools import combinations

INPUT_LIMIT = 1024 * 1024
MAX_CONTAINER_DEPTH = 64
IDENTIFIER = re.compile(r"[a-z][a-z0-9_-]{0,31}\Z")
BOARD_KEYS = {'version', 'unit', 'width', 'height', 'clearance', 'components', 'nets'}
COMPONENT_KEYS = {'id', 'x', 'y', 'width', 'height', 'pins'}
NET_KEYS = {'id', 'members'}
REF_KEYS = {'component', 'pin'}


def exact_keys(value, keys):
    return isinstance(value, dict) and value.keys() == keys


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def identifier(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def array(value, maximum):
    return isinstance(value, list) and len(value) <= maximum


def valid_board(board):
    if not exact_keys(board, BOARD_KEYS):
        return False
    if not integer(board['version'], 1, 1) or board['unit'] not in ('um', 'mm'):
        return False
    if not all(integer(board[k], 1, 1000000) for k in ('width', 'height')):
        return False
    if not integer(board['clearance'], 0, 1000000):
        return False
    if not array(board['components'], 128) or not array(board['nets'], 128):
        return False
    for component in board['components']:
        if not isinstance(component, dict) or not COMPONENT_KEYS <= component.keys() <= COMPONENT_KEYS | {'rotation'}:
            return False
        if not identifier(component['id']):
            return False
        if not all(integer(component[k], -1000000, 1000000) for k in ('x', 'y')):
            return False
        if not all(integer(component[k], 1, 1000000) for k in ('width', 'height')):
            return False
        rotation = component.get('rotation', 0)
        if type(rotation) is not int or rotation not in (0, 90, 180, 270):
            return False
        pins = component['pins']
        if not array(pins, 32) or not all(identifier(pin) for pin in pins):
            return False
        if len(set(pins)) != len(pins):
            return False
    for net in board['nets']:
        if not exact_keys(net, NET_KEYS) or not identifier(net['id']):
            return False
        if not array(net['members'], 128):
            return False
        for member in net['members']:
            if not exact_keys(member, REF_KEYS):
                return False
            if not all(identifier(member[k]) for k in REF_KEYS):
                return False
    return True


def references(refs):
    return [{'component': component, 'pin': pin} for component, pin in sorted(refs)]


def inspect_board(board):
    """Validate a parsed board and return its deterministic report."""
    if not valid_board(board):
        return {'error': 'invalid-board'}
    duplicate_components = sorted(k for k, n in Counter(c['id'] for c in board['components']).items() if n > 1)
    duplicate_nets = sorted(k for k, n in Counter(n['id'] for n in board['nets']).items() if n > 1)
    if duplicate_components or duplicate_nets:
        return {'error': 'duplicate-id', 'components': duplicate_components, 'nets': duplicate_nets}
    components = {c['id']: c for c in board['components']}
    uses = Counter((m['component'], m['pin']) for n in board['nets'] for m in n['members'])
    unknown = {ref for ref in uses if ref[0] not in components or ref[1] not in components[ref[0]]['pins']}
    if unknown:
        return {'error': 'unknown-pin', 'refs': references(unknown)}
    reused = {ref for ref, count in uses.items() if count > 1}
    if reused:
        return {'error': 'reused-pin', 'refs': references(reused)}

    scale = 1000 if board['unit'] == 'mm' else 1
    width, height, clearance = (board[k] * scale for k in ('width', 'height', 'clearance'))
    rectangles = {}
    for key, component in components.items():
        x, y, w, h = (component[k] * scale for k in ('x', 'y', 'width', 'height'))
        if component.get('rotation', 0) in (90, 270):
            w, h = h, w
        rectangles[key] = (x, y, w, h)
    findings = set()
    for key, (x, y, w, h) in rectangles.items():
        if x < 0 or y < 0 or x + w > width or y + h > height:
            findings.add(('outside-board', (key,)))
        for pin in components[key]['pins']:
            if (key, pin) not in uses:
                findings.add(('unconnected-pin', (key, pin)))
    for a, b in combinations(sorted(rectangles), 2):
        ax, ay, aw, ah = rectangles[a]
        bx, by, bw, bh = rectangles[b]
        gap_x = max(0, ax - (bx + bw), bx - (ax + aw))
        gap_y = max(0, ay - (by + bh), by - (ay + ah))
        overlap = max(ax, bx) < min(ax + aw, bx + bw) and max(ay, by) < min(ay + ah, by + bh)
        if overlap or gap_x * gap_x + gap_y * gap_y < clearance * clearance:
            findings.add(('clearance', (a, b)))
    reports = []
    for net in sorted(board['nets'], key=lambda n: n['id']):
        members = sorted((m['component'], m['pin']) for m in net['members'])
        if len(members) < 2:
            findings.add(('underconnected-net', (net['id'],)))
        centers = [(2 * rectangles[c][0] + rectangles[c][2], 2 * rectangles[c][1] + rectangles[c][3]) for c, _ in members]
        span = 0
        if centers:
            xs, ys = zip(*centers)
            span = (max(xs) - min(xs) + max(ys) - min(ys) + 1) // 2
        reports.append({'id': net['id'], 'members': references(members), 'span': span})
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">',
           f'<rect x="0" y="0" width="{width}" height="{height}" fill="white" stroke="black"/>']
    for key in sorted(rectangles):
        x, y, w, h = rectangles[key]
        svg.append(f'<rect id="{key}" x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="black"/>')
    svg.append('</svg>')
    return {'unit': 'um', 'findings': [{'code': code, 'subjects': list(subjects)} for code, subjects in sorted(findings)],
            'nets': reports, 'svg': ''.join(svg)}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate key')
        result[key] = value
    return result


def signed_integer(text):
    value = int(text)
    if not -(2 ** 63) <= value < 2 ** 63:
        raise ValueError('integer outside signed 64-bit range')
    return value


def finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise ValueError('nonfinite number')
    return value


def reject_constant(text):
    raise ValueError('nonfinite constant')


def check_container_depth(text):
    """Bound nesting before JSON parsing; JSON decoding owns syntax validation."""
    depth = 0
    in_string = False
    escaped = False
    for char in text:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char in '[{':
            depth += 1
            if depth > MAX_CONTAINER_DEPTH:
                raise ValueError('container nesting exceeds 64')
        elif char in ']}':
            depth -= 1


def check_unicode_scalars(value):
    """Check all decoded strings, including keys and schema-invalid content."""
    pending = [value]
    while pending:
        current = pending.pop()
        if isinstance(current, str):
            if any(0xD800 <= ord(char) <= 0xDFFF for char in current):
                raise ValueError('unpaired surrogate in JSON string')
        elif isinstance(current, dict):
            pending.extend(current.keys())
            pending.extend(current.values())
        elif isinstance(current, list):
            pending.extend(current)


def handle_request(raw):
    """Decode and inspect a UTF-8 request, containing all transport errors."""
    if len(raw) > INPUT_LIMIT:
        return {'error': 'invalid-request'}
    try:
        text = raw.decode('utf-8')
        check_container_depth(text)
        request = json.loads(text, object_pairs_hook=unique_object,
                             parse_int=signed_integer, parse_float=finite_float,
                             parse_constant=reject_constant)
        check_unicode_scalars(request)
    except (UnicodeError, ValueError, RecursionError):
        return {'error': 'invalid-request'}
    if not exact_keys(request, {'cases'}) or not array(request['cases'], 64):
        return {'error': 'invalid-request'}
    return {'results': [inspect_board(board) for board in request['cases']]}


def main():
    raw = sys.stdin.buffer.read(INPUT_LIMIT + 1)
    print(json.dumps(handle_request(raw), ensure_ascii=True, separators=(',', ':')))


if __name__ == '__main__':
    main()
