"""Coordinator-only pilot extensions; these tasks are separate, not cumulative."""
from . import planner_oracle as base
from .oracle_transport import respond


def priority_result(value):
    # Validate the optional field before delegating the unchanged v1 schema and
    # error precedence. Never mutate the caller's grading input.
    if not isinstance(value, dict) or not isinstance(value.get('jobs'), list):
        return {'error': 'invalid-manifest'}
    stripped = []
    priorities = {}
    for job in value['jobs']:
        if not isinstance(job, dict):
            return {'error': 'invalid-manifest'}
        priority = job.get('priority', 0)
        if type(priority) is not int or not -1000 <= priority <= 1000:
            return {'error': 'invalid-manifest'}
        stripped.append({key: item for key, item in job.items() if key != 'priority'})
        if base.identifier(job.get('id')):
            priorities[job['id']] = priority
    result = base.manifest_result(dict(value, jobs=stripped))
    if 'error' in result:
        return result
    dependencies = {job['id']: set(job['needs']) for job in stripped}
    done = set()
    order = []
    while len(done) < len(dependencies):
        ready = [name for name, needs in dependencies.items() if name not in done and needs <= done]
        chosen = min(ready, key=lambda name: (-priorities[name], name))
        done.add(chosen)
        order.append(chosen)
    return dict(result, order=order)


def cycle_groups_result(value):
    result = base.manifest_result(value)
    if result.get('error') != 'cycle':
        return result
    names = sorted(job['id'] for job in value['jobs'])
    indices = {name: index for index, name in enumerate(names)}
    reach = [0] * len(names)
    for job in value['jobs']:
        reach[indices[job['id']]] = sum(1 << indices[need] for need in job['needs'])
    # Transitive closure gives a deliberately different grading formulation from
    # a participant's likely Tarjan/DFS component implementation.
    for pivot in range(len(names)):
        for source in range(len(names)):
            if reach[source] & (1 << pivot):
                reach[source] |= reach[pivot]
    groups = []
    assigned = set()
    for source, name in enumerate(names):
        if name in assigned or not reach[source] & (1 << source):
            continue
        group = [other for target, other in enumerate(names)
                 if reach[source] & (1 << target) and reach[target] & (1 << source)]
        groups.append(group)
        assigned.update(group)
    return dict(result, cycles=sorted(groups))


HANDLERS = {'planner-priority': priority_result, 'planner-cycle-groups': cycle_groups_result,
            'planner-input-boundary': base.manifest_result}


def response(request, task):
    handler = HANDLERS[task]
    if (not isinstance(request, dict) or set(request) != {'cases'} or
            not isinstance(request['cases'], list) or len(request['cases']) > 64):
        return {'error': 'invalid-request'}
    return {'results': [handler(value) for value in request['cases']]}


def response_bytes(raw, task):
    if task not in HANDLERS:
        raise ValueError('unknown planner pilot task')
    return respond(raw, lambda request: response(request, task))
