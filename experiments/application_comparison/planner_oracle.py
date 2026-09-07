"""Coordinator-only workflow specification oracle; never mount for participants."""
import random
import re
from .oracle_transport import respond

IDENTIFIER = re.compile(r'[a-z][a-z0-9_-]{0,31}\Z')


def identifier(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def manifest_result(value):
    if (not isinstance(value, dict) or set(value) != {'version', 'jobs'} or
            type(value['version']) is not int or value['version'] != 1 or
            not isinstance(value['jobs'], list) or len(value['jobs']) > 128):
        return {'error': 'invalid-manifest'}
    jobs = value['jobs']
    for job in jobs:
        if (not isinstance(job, dict) or set(job) != {'id', 'duration', 'needs'} or
                not identifier(job['id']) or type(job['duration']) is not int or
                not 0 <= job['duration'] <= 1000000 or
                not isinstance(job['needs'], list) or len(job['needs']) > 128 or
                not all(identifier(item) for item in job['needs'])):
            return {'error': 'invalid-manifest'}
    names = [job['id'] for job in jobs]
    repeated = sorted({name for name in names if names.count(name) > 1})
    if repeated:
        return {'error': 'duplicate-id', 'ids': repeated}
    repeated_needs = sorted(job['id'] for job in jobs if len(set(job['needs'])) != len(job['needs']))
    if repeated_needs:
        return {'error': 'duplicate-dependency', 'jobs': repeated_needs}
    unknown = sorted({name for job in jobs for name in job['needs']} - set(names))
    if unknown:
        return {'error': 'unknown-dependency', 'ids': unknown}
    by_id = {job['id']: job for job in jobs}
    remaining = set(names)
    order = []
    while remaining:
        ready = sorted(name for name in remaining if not remaining.intersection(by_id[name]['needs']))
        if not ready:
            return {'error': 'cycle', 'blocked': sorted(remaining)}
        order.append(ready[0])
        remaining.remove(ready[0])
    remaining = set(names)
    layers = []
    while remaining:
        ready = sorted(name for name in remaining if not remaining.intersection(by_id[name]['needs']))
        layers.append(ready)
        remaining.difference_update(ready)
    finish = {}
    timing = {}
    for name in order:
        start = max((finish[need] for need in by_id[name]['needs']), default=0)
        finish[name] = start + by_id[name]['duration']
        timing[name] = {'id': name, 'start': start, 'finish': finish[name]}
    return {'order': order, 'layers': layers, 'timings': [timing[name] for name in sorted(names)],
            'makespan': max(finish.values(), default=0)}


def response(request):
    if (not isinstance(request, dict) or set(request) != {'cases'} or
            not isinstance(request['cases'], list) or len(request['cases']) > 64):
        return {'error': 'invalid-request'}
    return {'results': [manifest_result(value) for value in request['cases']]}


def response_bytes(raw):
    return respond(raw, response)


def generated_cases(seed, count=32):
    """Reproducible mixed DAG/cycle/error fixtures. Seeds are coordinator inputs."""
    if type(count) is not int or not 0 <= count <= 64:
        raise ValueError('case count must be 0..64')
    rng = random.Random(seed)
    cases = []
    for index in range(count):
        names = [f'j{number:03}' for number in range(rng.randint(1, 24))]
        rng.shuffle(names)
        jobs = [{'id': name, 'duration': rng.choice([0, 1, 1000000, rng.randrange(1000)]),
                 'needs': [prior for prior in names[:offset] if rng.random() < .2]}
                for offset, name in enumerate(names)]
        mode = index % 8
        if mode == 1:
            jobs[0]['needs'].append(names[0])
        elif mode == 2:
            jobs[-1]['needs'].append('absent')
        elif mode == 3:
            jobs.append(dict(jobs[0]))
        elif mode == 4:
            jobs[0]['needs'] = ['absent', 'absent']
        elif mode == 5:
            jobs[0]['duration'] = -1
        elif mode == 6:
            jobs = []
        rng.shuffle(jobs)
        cases.append({'version': 1, 'jobs': jobs})
    return {'cases': cases}
