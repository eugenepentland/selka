"""Coordinator-only task oracles; slack explicitly extends dependency-lag semantics."""
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


def normalize_lags(value):
    """Translate only the new edge representation; base owns phase precedence."""
    if not isinstance(value, dict) or not isinstance(value.get('jobs'), list):
        return None
    normalized = []
    for job in value['jobs']:
        if not isinstance(job, dict) or not isinstance(job.get('needs'), list):
            return None
        needs = []
        for edge in job['needs']:
            if isinstance(edge, str):
                name = edge
            elif (isinstance(edge, dict) and set(edge) == {'id', 'lag'} and
                  type(edge['lag']) is int and 0 <= edge['lag'] <= 1000000):
                name = edge['id']
            else:
                return None
            if not base.identifier(name):
                return None
            needs.append(name)
        normalized.append(dict(job, needs=needs))
    return dict(value, jobs=normalized)


def dependency_lags_result(value):
    normalized = normalize_lags(value)
    if normalized is None:
        return {'error': 'invalid-manifest'}
    result = base.manifest_result(normalized)
    if 'error' in result:
        return result
    jobs = {job['id']: job for job in value['jobs']}
    finish, timing = {}, {}
    for name in result['order']:
        job = jobs[name]
        starts = [finish[edge if isinstance(edge, str) else edge['id']] +
                  (0 if isinstance(edge, str) else edge['lag']) for edge in job['needs']]
        start = max(starts, default=0)
        finish[name] = start + job['duration']
        timing[name] = dict(id=name, start=start, finish=finish[name])
    return dict(result, timings=[timing[name] for name in sorted(jobs)],
                makespan=max(finish.values(), default=0))


def slack_result(value):
    result = dependency_lags_result(value)
    if 'error' in result:
        return result
    jobs = {job['id']: job for job in value['jobs']}
    successors = {name: [] for name in jobs}
    for name, job in jobs.items():
        for edge in job['needs']:
            source, lag = (edge, 0) if isinstance(edge, str) else (edge['id'], edge['lag'])
            successors[source].append((name, lag))
    # Maximum remaining path length, including this job's own execution, gives
    # the tightest common-deadline bound. This also constrains disconnected sinks.
    tail = {}
    for name in reversed(result['order']):
        tail[name] = jobs[name]['duration'] + max(
            (lag + tail[target] for target, lag in successors[name]), default=0)
    timings = []
    for timing in result['timings']:
        latest = result['makespan'] - tail[timing['id']]
        timings.append(dict(timing, latest_start=latest, slack=latest - timing['start']))
    return dict(result, timings=timings,
                critical=[timing['id'] for timing in timings if timing['slack'] == 0])


HANDLERS = {'planner-priority': priority_result, 'planner-cycle-groups': cycle_groups_result,
            'planner-input-boundary': base.manifest_result,
            'planner-dependency-lags': dependency_lags_result, 'planner-slack': slack_result}


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
