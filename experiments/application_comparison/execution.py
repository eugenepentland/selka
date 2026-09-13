"""Execute frozen candidates using coordinator-owned language command adapters."""
import json
import math
from pathlib import Path
import tempfile
from .isolation import Limits, run
from .inputs import payload
from .storage import canonical, digest, path_identity, snapshot, verify_snapshot, write_json


def freeze_adapter(language, tools, commands, limits=None):
    if language not in ('my', 'python', 'zig', 'rust'):
        raise ValueError('unknown language')
    if not commands or commands[-1]['phase'] != 'run':
        raise ValueError('adapter must end with one run phase')
    if sum(command['phase'] == 'run' for command in commands) != 1:
        raise ValueError('adapter must have exactly one run phase')
    if any(command['phase'] not in ('check', 'guardian', 'build', 'run') or
           not command['argv'] or any(not isinstance(x, str) or '\x00' in x for x in command['argv']) for command in commands):
        raise ValueError('invalid adapter command')
    limits = limits or Limits()
    limits.validate()
    body = {'language': language, 'tools': {name: path_identity(path) for name, path in tools.items()},
            'commands': commands, 'limits': limits.__dict__}
    return dict(body, sha256=digest(body))


def verify_adapter(adapter):
    body = {key: value for key, value in adapter.items() if key != 'sha256'}
    if digest(body) != adapter['sha256']:
        raise ValueError('adapter definition changed')
    for identity in adapter['tools'].values():
        if path_identity(identity['path']) != identity:
            raise ValueError('frozen tool or standard library changed')


def parse_output(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate response key')
            result[key] = value
        return result
    def nonfinite(value):
        raise ValueError('nonfinite response')
    def floating(value):
        result = float(value)
        if not math.isfinite(result):
            raise ValueError('nonfinite response')
        return result
    return json.loads(data, object_pairs_hook=unique, parse_constant=nonfinite, parse_float=floating)


def evaluate(source, receipt, adapter, request, directory, *, request_bytes=None, remaining_seconds=None, build_reuse=None):
    """No expected answer enters the execution environment. All phases are isolated."""
    input_bytes, input_receipt = payload(request, request_bytes)
    verify_snapshot(source, receipt)
    verify_adapter(adapter)
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    steps = []
    reuse = None
    eligible = build_reuse is not None and build_reuse.eligible(adapter)
    with tempfile.TemporaryDirectory(prefix='comparison-candidate-') as temporary:
        work = Path(temporary) / 'work'
        snapshot(source, work)
        cache = Path(temporary) / 'cache'
        cache.mkdir()
        if eligible:
            reuse = build_reuse.restore(receipt, adapter, cache)
        commands = adapter['commands'][-1:] if reuse else adapter['commands']
        for index, command in enumerate(commands):
            limits = Limits(**adapter['limits'])
            if remaining_seconds is not None:
                remaining = remaining_seconds()
                if remaining <= 0:
                    outcome = {'phase': command['phase'], 'passed': False, 'failure': 'phase-deadline'}
                    break
                limits = Limits(**dict(limits.__dict__, wall_seconds=min(limits.wall_seconds, remaining),
                                       cpu_seconds=min(limits.cpu_seconds, max(1, math.ceil(remaining)))))
            result = run(work, command['argv'], tools={name: tool['path'] for name, tool in adapter['tools'].items()},
                         cache=cache, limits=limits,
                         input_bytes=input_bytes if command['phase'] == 'run' else b'')
            stdout, stderr = result.pop('stdout'), result.pop('stderr')
            (directory / f'{index:02}.stdout').write_bytes(stdout)
            (directory / f'{index:02}.stderr').write_bytes(stderr)
            steps.append(dict(result, phase=command['phase']))
            if result['outcome'] != 'exited' or result['returncode'] != 0:
                outcome = {'phase': command['phase'], 'passed': False, 'failure': result['outcome']}
                break
            if eligible and reuse is None and index == len(commands) - 2:
                # Test/build steps may not change the checked application source.
                verify_snapshot(work, receipt)
                verify_adapter(adapter)
                reuse = build_reuse.capture(receipt, adapter, cache, directory, steps)
        else:
            try:
                output = parse_output(stdout)
                outcome = {'phase': 'behavior', 'passed': True, 'output': output}
            except (ValueError, UnicodeError, RecursionError) as error:
                outcome = {'phase': 'protocol', 'passed': False, 'failure': str(error)}
    # Results from a concurrently changed tool or captured source are invalid.
    verify_adapter(adapter)
    verify_snapshot(source, receipt)
    record = {'version': 'application-check-v2', 'source_sha256': receipt['sha256'],
              'adapter_sha256': adapter['sha256'], 'request_sha256': input_receipt['sha256'],
              'input': input_receipt,
              'steps': steps, 'outcome': outcome}
    if reuse is not None:
        record['build_reuse'] = reuse
    write_json(directory / 'result.json', record)
    return record


def correct(outcome, expected):
    return outcome['passed'] and outcome['phase'] == 'behavior' and canonical(outcome['output']) == canonical(expected)
