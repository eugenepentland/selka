#!/usr/bin/env python3
"""Execute the frozen public guest contracts through the supported test command.

Owns bounded shared admission. Source refusals and files with a separate main or
importer contract remain explicit inventory rows, never empty execution passes.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
import census


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('compiler', 'zig', 'source-report', 'property-report', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--modes', nargs='+', choices=census.MODES, default=list(census.MODES))
    parser.add_argument('--ownership', choices=('opt-in', 'default'), default='opt-in')
    args = parser.parse_args()
    for key in ('compiler', 'zig', 'source_report', 'property_report', 'output'):
        setattr(args, key, getattr(args, key).resolve())
    source_report = json.loads(args.source_report.read_text())
    prior_properties = json.loads(args.property_report.read_text())
    tree = Path(source_report['fixture_root'])
    compiler_hash = census.digest(args.compiler)
    assert compiler_hash == source_report['compiler_sha256'] == prior_properties['compiler_sha256']
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)
    temporary = args.output / 'tmp'
    temporary.mkdir()
    env['TMPDIR'] = str(temporary)
    report = {'schema': 'a03-common-guest-tests-v1', 'compiler': str(args.compiler),
              'compiler_sha256': compiler_hash, 'fixture_commit': source_report['fixture_commit'],
              'fixture_root': str(tree), 'source_report_sha256': census.digest(args.source_report),
              'property_report_sha256': census.digest(args.property_report),
              'harness_sha256': census.digest(__file__), 'census_helper_sha256': census.digest(census.__file__),
              'ownership': args.ownership, 'modes': args.modes, 'seed': 7, 'property_runs': 12,
              'scope': 'Real guest test command with leakcheck; uninstrumented, no measured RC-event claim.',
              'cases': {}, 'failures': []}
    (args.output / 'harness.py.snapshot').write_bytes(Path(__file__).read_bytes())
    (args.output / 'census.py.snapshot').write_bytes(Path(census.__file__).read_bytes())
    selected = [row for row in source_report['cases'] if row['group'] == 'guest-64']
    assert len(selected) == 64
    for case in selected:
        source = tree / case['source']
        assert census.digest(source) == case['sha256']
        names = re.findall(r'^public func (test_\w+)\(', source.read_text(), re.M)
        row = report['cases'][case['source']] = {
            'source_sha256': case['sha256'], 'source_status': case['status'],
            'expected_tests': names, 'modes': {}}
        if case['status'] != 'admitted':
            row['status'] = 'blocked_source_refusal'
            row['source_diagnostic'] = case['check']['stderr']
        elif not names:
            row['status'] = 'separate_main_or_importer_contract_required'
        elif case['source'] == 'tests/lang/properties.my':
            assert case['sha256'] == prior_properties['source_sha256']
            row['reused_evidence'] = str(args.property_report)
            row['modes'] = prior_properties['modes']
            row['status'] = 'reused_same_artifact_execution'
        else:
            row['status'] = 'pending'
    lease = census.AdmissionLease(args.output, env, 50, 30)
    census.LEASE = lease
    flags = ['--experimental-zero-rc'] if args.ownership == 'opt-in' else []
    try:
        # Complete a release sweep before the remaining modes to expose blockers early.
        for mode in args.modes:
            for case in selected:
                row = report['cases'][case['source']]
                if row['status'] not in ('pending', 'executed'):
                    continue
                source = tree / case['source']
                assert census.digest(source) == case['sha256']
                raw = args.output / 'raw' / case['source'] / mode
                result = census.invoke([
                    args.compiler, 'test', source, *flags, *census.MODES[mode],
                    '--force', '--json', '--jobs', '1', '--seed', '7', '--property-runs', '12',
                    '--zig', args.zig, '--cache-dir', args.output / 'cache' / mode,
                ], raw / 'command', env, admitted=True, timeout=240)
                try:
                    parsed = json.loads(result['stdout'])
                except ValueError:
                    parsed = None
                lane = {'command': result, 'json_report': parsed, 'passed': False}
                if parsed is not None:
                    names = [test['name'].split('::')[-1] for test in parsed.get('tests', [])]
                    lane['passed'] = (
                        result['exit'] == 0 and set(names) == set(row['expected_tests'])
                        and len(names) == len(row['expected_tests'])
                        and parsed.get('passed') == len(names)
                        and all(parsed.get(key) == 0 for key in ('failed', 'skipped', 'cached', 'unsupported'))
                        and all(test.get('status') == 'passed'
                                and test.get('cache', {}).get('action') == 'execute'
                                for test in parsed['tests']))
                row['modes'][mode] = lane
                row['status'] = 'executed'
                if not lane['passed']:
                    report['failures'].append(case['source'] + '/' + mode)
                census.save(args.output / 'results.json', report)
                print(case['source'], mode, 'passed' if lane['passed'] else 'FAILED',
                      result['stderr'].split('\n')[0], flush=True)
                assert census.digest(source) == case['sha256']
    finally:
        lease.close()
        census.save(args.output / 'results.json', report)
    assert compiler_hash == census.digest(args.compiler)
    return bool(report['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
