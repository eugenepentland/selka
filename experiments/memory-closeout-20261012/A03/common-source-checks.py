#!/usr/bin/env python3
"""Check all 64+23 A06 sources in an immutable tree; never migrate source text.

This adapter owns bounded shared build admission. Do not add a build-slot wrapper.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
import census


def inventory(tree):
    location = tree / 'experiments/memory-closeout-20261012/A06'
    groups = {
        'guest-64': [entry['source'] for entry in json.loads(
            (location / 'guest-migrations/originals.json').read_text())
            if entry['source'] != 'tests/lang/frontend_type_helpers.my'],
        'additional-23': [entry['source'] for entry in json.loads(
            (location / 'additional-migrations/before.json').read_text())['cases']],
    }
    assert len(groups['guest-64']) == 64
    assert len(groups['additional-23']) == 23
    assert len(set(sum(groups.values(), []))) == 87
    return [{'group': group, 'source': source, 'sha256': census.digest(tree / source)}
            for group, sources in groups.items() for source in sources]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('fixture-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--fixture-commit', required=True)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--compiler-sha256')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--ownership', choices=('opt-in', 'default'), default='opt-in')
    args = parser.parse_args()
    args.fixture_root = args.fixture_root.resolve()
    args.output = args.output.resolve()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                       cwd=args.fixture_root, text=True).strip()
    if revision != args.fixture_commit:
        parser.error('frozen fixture revision differs from declared revision')
    cases = inventory(args.fixture_root)
    args.output.mkdir(parents=True, exist_ok=False)
    report = {'schema': 'a03-common-source-checks-v1', 'fixture_commit': revision,
              'fixture_root': str(args.fixture_root), 'harness_sha256': census.digest(__file__),
              'census_helper_sha256': census.digest(census.__file__), 'manifest': cases,
              'ownership': args.ownership, 'source_mutations_allowed': False,
              'scope': 'Source admission only; no native execution claimed.', 'cases': []}
    census.save(args.output / 'manifest.json', report)
    (args.output / 'harness.py.snapshot').write_bytes(Path(__file__).read_bytes())
    if args.prepare_only:
        print('Prepared 87 source identities:', args.output, flush=True)
        return 0
    if args.compiler is None or args.compiler_sha256 is None:
        parser.error('execution requires compiler and expected compiler-sha256')
    args.compiler = args.compiler.resolve()
    if census.digest(args.compiler) != args.compiler_sha256:
        parser.error('compiler identity differs from completed artifact identity')
    report.update(compiler=str(args.compiler), compiler_sha256=args.compiler_sha256)
    env = dict(os.environ)
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)
    temporary = args.output / 'tmp'
    temporary.mkdir()
    env['TMPDIR'] = str(temporary)
    lease = census.AdmissionLease(args.output, env, 50, 30)
    census.LEASE = lease
    try:
        for case in cases:
            source = args.fixture_root / case['source']
            assert census.digest(source) == case['sha256'], 'frozen source changed before check'
            flags = ['--experimental-zero-rc'] if args.ownership == 'opt-in' else []
            checked = census.invoke([args.compiler, 'check', source, '--no-cache', *flags],
                                    args.output / 'raw' / case['group'] / source.stem,
                                    env, admitted=True, timeout=120)
            status = ('admitted' if checked['exit'] == 0 else
                      'refused' if checked['exit'] == 1 and 'error[E_' in checked['stderr'] else
                      'compiler_or_tool_failure')
            report['cases'].append({**case, 'status': status, 'check': checked})
            assert census.digest(source) == case['sha256'], 'frozen source changed during check'
            census.save(args.output / 'results.json', report)
            print(case['source'], status, checked['stderr'].split('\n')[0], flush=True)
    finally:
        lease.close()
        report['summary'] = {status: sum(row['status'] == status for row in report['cases'])
                             for status in ('admitted', 'refused', 'compiler_or_tool_failure')}
        report['summary']['unmeasured'] = len(cases) - len(report['cases'])
        census.save(args.output / 'results.json', report)
    assert census.digest(args.compiler) == args.compiler_sha256, 'compiler changed during checks'
    assert inventory(args.fixture_root) == cases, 'frozen sources changed during checks'
    return report['summary']['admitted'] != 87


if __name__ == '__main__':
    raise SystemExit(main())
