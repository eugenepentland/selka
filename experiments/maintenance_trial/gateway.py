"""Coordinator-owned measured commands over the existing Linux isolation boundary."""
import argparse
import json
import math
import os
from pathlib import Path
import sys
import time
from pack import authoring_receipt, source_receipt
from experiments.application_comparison.isolation import Limits, run
from experiments.application_comparison.storage import (
    locked, path_identity, read_json, snapshot, verify_snapshot, write_json,
)


def event(directory, value):
    with (directory / 'gateway.jsonl').open('a') as stream:
        stream.write(json.dumps(value, sort_keys=True) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def begin(directory, docs=None):
    with locked(directory):
        if (directory / 'gateway.json').exists() or (directory / 'seal.json').exists():
            raise ValueError('gateway already begun or submission sealed')
        setup = read_json(directory / 'setup.json')
        if authoring_receipt() != setup['authoring']:
            raise ValueError('authoring changed before gateway start')
        verify_snapshot(directory / 'public/work', setup['start'])
        state = {'started_unix': time.time(), 'started_monotonic': time.monotonic(),
                 'requests': 0, 'commands': 0, 'edited_checks': 0, 'last_checked': setup['start'],
                 'expected_source': setup['start'], 'has_check': False, 'pending': None, 'docs': path_identity(docs) if docs else None}
        (directory / 'commands').mkdir()
        write_json(directory / 'gateway.json', state)
        event(directory, {'event': 'begin', 'time': state['started_unix'], 'budget': setup['budget']})
        return {'started': True, 'budget': setup['budget']}


def remaining(setup, state):
    elapsed = max(time.time() - state['started_unix'], time.monotonic() - state['started_monotonic'])
    return setup['budget']['wall_seconds'] - elapsed


def fixed_public(directory, setup):
    from experiments.application_comparison.storage import inventory, source_files
    captured = source_files(directory / 'public', max_files=16, max_bytes=1024 * 1024)
    expected_names = set(setup['public_fixed']) | {'work/' + name for name in setup['start']['files']}
    if set(captured) != expected_names:
        raise ValueError('files outside the three editable modules were added or removed')
    files = {name: captured[name] for name in setup['public_fixed']}
    if inventory(files) != setup['public_fixed']:
        raise ValueError('public task or checking tools changed')


def command(directory, operation, argv):
    if operation not in ('run', 'check') or (operation == 'check' and argv):
        raise ValueError('expected run argv or argument-free check')
    if operation == 'run' and (not argv or len(argv) > 128 or len(json.dumps(argv)) > 65536):
        raise ValueError('bounded nonempty argv required')
    with locked(directory):
        setup, state = read_json(directory / 'setup.json'), read_json(directory / 'gateway.json')
        state['requests'] += 1
        write_json(directory / 'gateway.json', state)
        event(directory, {'event': 'request', 'request': state['requests'], 'time': time.time(), 'operation': operation, 'argv': argv})
        if (directory / 'seal.json').exists() or state['pending'] is not None:
            raise ValueError('sealed or incomplete command requires coordinator review')
        if (state['requests'] > setup['budget']['tool_invocations'] or
                state['edited_checks'] >= setup['budget']['edited_submissions'] or remaining(setup, state) <= 0):
            event(directory, {'event': 'budget-rejection', 'time': time.time(), 'operation': operation})
            raise ValueError('trial command, edited-check or wall budget exhausted')
        if authoring_receipt() != setup['authoring'] or path_identity(setup['compiler']['path']) != setup['compiler']:
            raise ValueError('frozen compiler or authoring identity changed')
        fixed_public(directory, setup)
        before = source_receipt(directory / 'public/work')
        if before != state['expected_source']:
            event(directory, {'event': 'unrecorded-edit', 'time': time.time(), 'source': before})
            raise ValueError('source changed outside the command gateway')
        edited = operation == 'check' and before != state['last_checked']
        tools = {'compiler': setup['compiler']['path']}
        if state['docs']:
            if path_identity(state['docs']['path']) != state['docs']:
                raise ValueError('frozen documentation changed')
            tools['docs'] = state['docs']['path']
        if operation == 'check':
            argv = ['/usr/bin/python3', 'check.py', '--compiler', '/tools/compiler', '--stage', str(setup['stage'])]
        number = state['commands'] + 1
        output = directory / 'commands' / f'{number:03}'
        output.mkdir()
        snapshot(directory / 'public/work', output / 'before')
        started, clock = time.time(), time.monotonic()
        request = {'event': 'start', 'index': number, 'operation': operation, 'argv': argv,
                   'time': started, 'source_before': before, 'edited_check': edited}
        write_json(output / 'request.json', request)
        state.update(commands=number, pending=number)
        if edited:
            state['edited_checks'] += 1
        write_json(directory / 'gateway.json', state)
        event(directory, request)
        # Isolation failure remains a recorded tool outcome; never run unrestricted fallback.
        seconds = max(0.001, min(60.0, remaining(setup, state)))
        try:
            result = run(directory / 'public', argv, tools=tools,
                         limits=Limits(wall_seconds=seconds, cpu_seconds=max(1, math.ceil(seconds))))
            stdout, stderr = result.pop('stdout'), result.pop('stderr')
        except Exception as error:
            result = {'outcome': 'infrastructure-error', 'returncode': None, 'isolated': False,
                      'error': type(error).__name__ + ': ' + str(error)}
            stdout, stderr = b'', b''
        (output / 'stdout').write_bytes(stdout)
        (output / 'stderr').write_bytes(stderr)
        boundary_error = None
        try:
            after = source_receipt(directory / 'public/work')
            snapshot(directory / 'public/work', output / 'after')
            fixed_public(directory, setup)
            if operation == 'check' and after != before:
                raise ValueError('public check changed source')
        except (ValueError, OSError) as error:
            after, boundary_error = None, str(error)
        record = {'event': 'end', 'index': number, 'time': time.time(),
                  'duration_seconds': time.monotonic() - clock, 'source_before': before,
                  'source_after': after, 'boundary_error': boundary_error, **result}
        write_json(output / 'result.json', record)
        event(directory, record)
        if boundary_error is None:
            state['pending'] = None
            state['expected_source'] = after
            if operation == 'check':
                state.update(last_checked=before, has_check=True)
        write_json(directory / 'gateway.json', state)
        return {'index': number, 'outcome': result['outcome'], 'returncode': result['returncode'],
                'duration_seconds': record['duration_seconds'], 'boundary_error': boundary_error,
                'commands': state['commands'], 'edited_checks': state['edited_checks'],
                'remaining_seconds': max(0, remaining(setup, state)),
                'stdout': stdout.decode(errors='replace'), 'stderr': stderr.decode(errors='replace')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('operation', choices=('begin', 'run', 'check'))
    parser.add_argument('--docs', type=Path)
    args, argv = parser.parse_known_args()
    if argv[:1] == ['--']:
        argv = argv[1:]
    if args.operation == 'begin':
        if argv:
            parser.error('begin takes only --docs')
        result = begin(args.directory.resolve(), args.docs.resolve() if args.docs else None)
    else:
        result = command(args.directory.resolve(), args.operation, argv)
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(json.dumps({'outcome': 'rejected', 'error': str(error)}))
        raise SystemExit(1)
