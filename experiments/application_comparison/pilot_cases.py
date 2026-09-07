"""Pilot grading-case authoring. Seeds and hidden outputs stay with the coordinator."""
import base64
import copy
import random
from . import eda_oracle, planner_oracle, eda_pilot_oracle, planner_pilot_oracle

TASKS = tuple(planner_pilot_oracle.HANDLERS) + tuple(eda_pilot_oracle.HANDLERS)


def planner():
    return {'version': 1, 'jobs': [dict(id='a', duration=2, needs=[]),
                                 dict(id='b', duration=3, needs=[]),
                                 dict(id='c', duration=1, needs=['a'])]}


def eda():
    return dict(version=1, unit='um', width=10, height=10, clearance=1,
                components=[dict(id='a', x=0, y=0, width=3, height=1, pins=['p', 'q']),
                            dict(id='b', x=4, y=0, width=1, height=3, pins=['p'])],
                nets=[dict(id='n', members=[dict(component='a', pin='p'), dict(component='b', pin='p')])])


def feature_examples(task):
    cases = []
    if task == 'planner-priority':
        for priorities in ((0, 0, 0), (-1000, 1000, 1), (1, 0, 1000), (-1, -1, 0)):
            value = planner()
            for job, priority in zip(value['jobs'], priorities):
                job['priority'] = priority
            cases.append(value)
        for invalid in (True, None, 0.0, -1001, 1001, '1'):
            value = planner()
            value['jobs'][0]['priority'] = invalid
            cases.append(value)
    elif task == 'planner-cycle-groups':
        for dependencies in ((['b'], ['a'], ['a']), (['a'], ['b'], []),
                             (['b'], ['a', 'c'], ['b']), ([], ['c'], ['b'])):
            value = planner()
            for job, needs in zip(value['jobs'], dependencies):
                job['needs'] = needs
            cases.append(value)
    elif task == 'eda-pin-roles':
        for left in ('passive', 'input', 'output'):
            for right in ('passive', 'input', 'output'):
                value = eda()
                value['components'][0]['pin_roles'] = [dict(pin='p', role=left), dict(pin='q', role='input')]
                value['components'][1]['pin_roles'] = [dict(pin='p', role=right)]
                cases.append(value)
        for invalid in (None, [dict(pin='missing', role='input')], [dict(pin='p', role='input')] * 2,
                        [dict(pin='p', role='driver')], [dict(pin='p', role='input', extra=True)]):
            value = eda()
            value['components'][0]['pin_roles'] = invalid
            cases.append(value)
    elif task == 'eda-rotation':
        for rotation in (0, 90, 180, 270, True, 90.0, None, -90, 360):
            value = eda()
            value['components'][0].update(rotation=rotation, x=9)
            cases.append(value)
        value = eda()
        value['components'][0]['rotation'] = 90
        value['components'][1].update(x=3, y=0)
        cases.append(value)
    elif task == 'eda-clearance-boundary':
        # Squared gaps: below, exactly at, and above a 3-4-5 diagonal.
        for clearance in (4, 5, 6):
            value = eda()
            value['clearance'] = clearance
            value['components'][1].update(x=6, y=5)
            cases.append(value)
        for x in (2, 3, 4):
            value = eda()
            value['clearance'] = 0
            value['components'][1]['x'] = x
            cases.append(value)
    return cases


def build(task, *, seed, public=False):
    if task not in TASKS or not isinstance(seed, str) or not seed:
        raise ValueError('known task and explicit nonempty seed required')
    oracle = planner_pilot_oracle if task.startswith('planner-') else eda_pilot_oracle
    original = planner_oracle if task.startswith('planner-') else eda_oracle
    cases = []
    def add(name, request):
        cases.append({'name': name, 'case': {'request': request, 'expected': oracle.response(request, task)}})
    def raw(name, data):
        cases.append({'name': name, 'case': {'request_base64': base64.b64encode(data).decode(),
                                           'expected': oracle.response_bytes(data, task)}})
    examples = feature_examples(task)
    add('documented-behavior', {'cases': examples[:9] if public else examples})
    if public:
        add('original-behavior', {'cases': [planner() if task.startswith('planner-') else eda()]})
    else:
        add('original-regressions', original.generated_cases(seed + ':original', 64))
        rng = random.Random(seed)
        generated = copy.deepcopy(original.generated_cases(seed + ':extended', 64))
        for value in generated['cases']:
            if task == 'planner-priority':
                for job in value['jobs']:
                    if rng.choice((True, False)):
                        job['priority'] = rng.randint(-1000, 1000)
            elif task == 'eda-rotation':
                for component in value['components']:
                    component['rotation'] = rng.choice((0, 90, 180, 270))
            elif task == 'eda-pin-roles':
                for component in value['components']:
                    component['pin_roles'] = [dict(pin=pin, role=rng.choice(('passive', 'input', 'output')))
                                              for pin in component['pins'] if rng.choice((True, False))]
        add('generated-maintenance', generated)
        if task == 'planner-cycle-groups':
            # Disjoint hidden graph shapes include multi-job SCCs, a one-way
            # connection between SCCs, and removable upstream/blocked downstream.
            cyclic = []
            for size in (2, 4, 7, 12):
                names = [f'node{rng.randrange(1000000):06}-{index}' for index in range(size * 2 + 2)]
                jobs = [dict(id=names[0], duration=0, needs=[])]
                for offset in range(2):
                    group = names[1 + offset * size:1 + (offset + 1) * size]
                    for index, name in enumerate(group):
                        needs = [group[(index + 1) % size]]
                        if index == 0:
                            needs.append(names[0] if offset == 0 else names[1])
                        jobs.append(dict(id=name, duration=rng.randrange(10), needs=needs))
                jobs.append(dict(id=names[-1], duration=1, needs=[names[size + 1]]))
                rng.shuffle(jobs)
                cyclic.append(dict(version=1, jobs=jobs))
            add('private-multiple-cycle-groups', {'cases': cyclic})
        if task == 'eda-clearance-boundary':
            large = []
            for unit in ('um', 'mm'):
                for clearance in (499999, 500000, 500001):
                    value = eda()
                    value.update(unit=unit, width=1000000, height=1000000, clearance=clearance)
                    value['components'][0].update(x=-500000, y=-500000, width=1, height=1)
                    value['components'][1].update(x=-199999, y=-99999, width=1, height=1)
                    large.append(value)
            # Two encodings of the same physical geometry must match exactly,
            # including SVG, spans and finding order.
            millimeters = eda()
            millimeters.update(unit='mm', clearance=5)
            millimeters['components'][1].update(x=6, y=5)
            micrometers = copy.deepcopy(millimeters)
            micrometers['unit'] = 'um'
            for key in ('width', 'height', 'clearance'):
                micrometers[key] *= 1000
            for component in micrometers['components']:
                for key in ('x', 'y', 'width', 'height'):
                    component[key] *= 1000
            add('large-clearance-arithmetic', {'cases': large})
            add('equivalent-unit-geometry', {'cases': [millimeters, micrometers]})
        for name, data in [('duplicate-key', b'{"cases":[],"cases":[]}'), ('invalid-utf8', b'\xff'),
                           ('nonfinite', b'{"cases":[1e999]}'), ('empty-input', b'')]:
            raw(name, data)
    if task == 'planner-input-boundary':
        # Different valid content/whitespace keeps public and private boundary
        # requests distinct while preserving the same externally specified limit.
        prefix = b'{"cases":[]}' if public else b'{"cases":[{"version":1,"jobs":[]}]}'
        for offset in ((0,) if public else (-1, 0, 1)):
            data = prefix + (b' ' if public else b'\n') * (1048576 + offset - len(prefix))
            raw(f'input-limit-{offset + 1}', data)
        if not public:
            unicode_prefix = '{"cases":["é"]}'.encode('utf-8')
            for offset in (0, 1):
                raw(f'utf8-byte-limit-{offset}', unicode_prefix + b' ' * (1048576 + offset - len(unicode_prefix)))
            malformed = b'{"cases":[],"cases":[]}'
            raw('malformed-at-limit', malformed + b' ' * (1048576 - len(malformed)))
            raw('trailing-data-at-limit', prefix + b' ' * (1048576 - len(prefix) - 1) + b'x')
    return cases
