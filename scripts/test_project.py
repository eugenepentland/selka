#!/usr/bin/env python3
"""Discover exported test_* guest functions and compare schema-pinned typed results."""
import argparse
import fnmatch
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import navigate
import test_providers


def command(compiler, entry, action, *flags):
    return subprocess.run([str(compiler), action, str(entry), *flags],
                          capture_output=True, text=True, timeout=60)


def run(compiler, entry, pattern='*', cases=None):
    compiler, entry = Path(compiler).resolve(), Path(entry).resolve()
    cases = cases or {}
    index, _ = navigate.load(compiler, entry)
    if not index['checked']:
        raise ValueError('test project does not check')
    before = navigate.sources(entry.parent)
    navigate.validate(index, before, index['snapshot']['implementation']['compiler_sha256'])
    schema_run = command(compiler, entry, 'schema-project')
    if schema_run.returncode:
        raise ValueError(schema_run.stderr)
    schema = json.loads(schema_run.stdout)
    schema_hash = navigate.digest(schema)
    locations = {item['id']: item['location'] for item in index['symbols']}
    discovered = [f for f in schema['functions'] if f['name'].split('::')[-1].startswith('test_')]
    unknown = set(cases) - {f['name'] for f in discovered}
    if unknown:
        raise ValueError('case settings name undiscovered tests: ' + ', '.join(sorted(unknown)))
    rows = []
    with tempfile.TemporaryDirectory(prefix='mylang-tests-') as temporary:
        request_path = Path(temporary) / 'request.json'
        for function in discovered:
            name = function['name']
            if not fnmatch.fnmatchcase(name, pattern):
                continue
            settings = cases.get(name, {})
            row = {'name': name, 'location': locations.get(name)}
            if settings.get('skip'):
                rows.append(dict(row, status='skipped', reason=settings['skip']))
                continue
            if 'expected' not in settings and function['result'] != 'bool':
                raise ValueError(name + ': non-boolean test requires expected typed JSON value')
            expected = settings.get('expected', True)
            invocation_entry, invocation_schema = entry, schema_hash
            if 'providers' in settings:
                invocation_entry, identity = test_providers.snapshot(entry, before, settings['providers'], Path(temporary) / str(len(rows)))
                provider_schema = command(compiler, invocation_entry, 'schema-project')
                if provider_schema.returncode:
                    raise ValueError(name + ': injected provider project does not check: ' + provider_schema.stderr)
                replacement_schema = json.loads(provider_schema.stdout)
                selected = next((f for f in replacement_schema['functions'] if f['name'] == name), None)
                if selected is None or selected['result'] != function['result'] or selected['parameters'] != function['parameters'] or replacement_schema['types'] != schema['types']:
                    raise ValueError(name + ': providers changed the test call signature')
                invocation_schema = navigate.digest(replacement_schema)
                row['provider_snapshot_sha256'] = identity
            request_path.write_text(json.dumps({'version': 'typed-call-v1',
                'schema_sha256': invocation_schema, 'function': name,
                'arguments': settings.get('arguments', {})}))
            result = command(compiler, invocation_entry, 'invoke-project', '--request=' + str(request_path),
                             '--diagnostics=json', '--max-codec-steps=1000000')
            if result.returncode:
                status = 'trap' if 'InvocationTrap' in result.stderr else 'infrastructure-failure'
                rows.append(dict(row, status=status, diagnostics=result.stderr))
            else:
                actual = json.loads(result.stdout)['value']
                # Typed JSON distinguishes booleans and integer strings, as well as structures.
                same = json.dumps(actual, sort_keys=True) == json.dumps(expected, sort_keys=True)
                rows.append(dict(row, status='passed' if same else 'failed', expected=expected, actual=actual))
    if navigate.sources(entry.parent) != before:
        raise ValueError('source changed during test run; results discarded')
    if hashlib.sha256(navigate.bounded_read(compiler, 256 * 1024 * 1024)).hexdigest() != index['snapshot']['implementation']['compiler_sha256']:
        raise ValueError('compiler changed during test run; results discarded')
    status = 'empty' if not rows else 'failed' if any(r['status'] not in ('passed', 'skipped') for r in rows) else 'skipped' if all(r['status'] == 'skipped' for r in rows) else 'passed'
    return {'version': 'guest-tests-v1', 'status': status, 'snapshot_sha256': index['snapshot_sha256'], 'tests': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('entry', type=Path)
    parser.add_argument('--compiler', type=Path, default=Path(__file__).resolve().parents[1] / 'zig-out/bin/mylang')
    parser.add_argument('--filter', default='*')
    parser.add_argument('--cases', type=Path, help='JSON object mapping qualified tests to arguments/expected/skip')
    args = parser.parse_args()
    try:
        cases = json.loads(args.cases.read_text()) if args.cases else None
        report = run(args.compiler, args.entry, args.filter, cases)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'version': 'guest-tests-v1', 'status': 'infrastructure-failure', 'message': str(error)}))
        return 2
    print(json.dumps(report, ensure_ascii=False))
    return {'passed': 0, 'failed': 1, 'empty': 3, 'skipped': 3}[report['status']]


if __name__ == '__main__':
    sys.exit(main())
