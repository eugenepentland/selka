"""Coordinator-only, independent EDA pilot task expectations; never participant tools."""
from . import eda_oracle as base
from .oracle_transport import respond


def strip_extension(board, field):
    if not isinstance(board, dict) or not isinstance(board.get('components'), list):
        return None
    if any(not isinstance(component, dict) for component in board['components']):
        return None
    stripped = dict(board, components=[{key: value for key, value in component.items() if key != field}
                                      for component in board['components']])
    return stripped if base.schema(stripped) else None


def rotation_result(board):
    occupied = strip_extension(board, 'rotation')
    if occupied is None:
        return {'error': 'invalid-board'}
    for original, component in zip(board['components'], occupied['components']):
        rotation = original.get('rotation', 0)
        if type(rotation) is not int or rotation not in (0, 90, 180, 270):
            return {'error': 'invalid-board'}
        if rotation in (90, 270):
            component['width'], component['height'] = component['height'], component['width']
    return base.board_result(occupied)


def pin_roles_result(board):
    stripped = strip_extension(board, 'pin_roles')
    if stripped is None:
        return {'error': 'invalid-board'}
    roles = {}
    for component in board['components']:
        assignments = component.get('pin_roles', [])
        if not isinstance(assignments, list) or len(assignments) > 32:
            return {'error': 'invalid-board'}
        assigned = set()
        for assignment in assignments:
            if (not isinstance(assignment, dict) or set(assignment) != {'pin', 'role'} or
                    not base.identifier(assignment['pin']) or assignment['pin'] not in component['pins'] or
                    assignment['role'] not in ('passive', 'input', 'output') or assignment['pin'] in assigned):
                return {'error': 'invalid-board'}
            assigned.add(assignment['pin'])
            roles[(component['id'], assignment['pin'])] = assignment['role']
    result = base.board_result(stripped)
    if 'error' in result:
        return result
    findings = list(result['findings'])
    for net in board['nets']:
        members = [roles.get((ref['component'], ref['pin']), 'passive') for ref in net['members']]
        if members.count('output') >= 2:
            findings.append({'code': 'multiple-drivers', 'subjects': [net['id']]})
        if 'input' in members and 'output' not in members:
            findings.append({'code': 'undriven-input-net', 'subjects': [net['id']]})
    return dict(result, findings=sorted(findings, key=lambda item: (item['code'], item['subjects'])))


HANDLERS = {'eda-rotation': rotation_result, 'eda-pin-roles': pin_roles_result,
            'eda-clearance-boundary': base.board_result}


def response(request, task):
    handler = HANDLERS[task]
    if (not isinstance(request, dict) or set(request) != {'cases'} or
            not isinstance(request['cases'], list) or len(request['cases']) > 64):
        return {'error': 'invalid-request'}
    return {'results': [handler(board) for board in request['cases']]}


def response_bytes(raw, task):
    if task not in HANDLERS:
        raise ValueError('unknown EDA pilot task')
    return respond(raw, lambda request: response(request, task))
