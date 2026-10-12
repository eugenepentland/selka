#!/usr/bin/env python3
"""Qualify a frozen assigned-source manifest with separate admission and execution.

This runner owns bounded build admission. Never wrap it in build-slot.sh.
The source manifest and original oracles remain unchanged after a refusal.
"""
import argparse
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import census


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--compiler-commit', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--case', action='append', default=[])
    parser.add_argument('--modes', nargs='+', choices=census.MODES, default=list(census.MODES))
    parser.add_argument('--ownership', choices=['opt-in', 'default'], default='opt-in')
    args = parser.parse_args()
    for key in ('manifest', 'compiler', 'zig', 'output'):
        setattr(args, key, getattr(args, key).resolve())
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = json.loads(args.manifest.read_text())
    selected = [case for case in manifest['cases'] if not args.case or case['id'] in args.case]
    if not selected:
        raise SystemExit('no selected cases')
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)
    audit = census.load_helper('a03_assigned_audit', 'experiments/zero-rc-20261011/audit.py')
    historical = census.load_helper('a03_assigned_counter_summary', 'experiments/rc-census-20261010/census.py')
    lease = census.AdmissionLease(args.output, env, 10)
    census.LEASE = lease
    result = {'schema': 'a03-assigned-qualification-v1', 'compiler_commit': args.compiler_commit,
              'compiler_path': str(args.compiler), 'compiler_sha256': census.digest(args.compiler),
              'manifest_sha256': census.digest(args.manifest), 'harness_sha256': census.digest(__file__),
              'census_helper_sha256': census.digest(census.__file__), 'ownership': args.ownership,
              'check_only': args.check_only, 'assigned_files': manifest['assigned_files'],
              'selected_cases': [case['id'] for case in selected], 'modes': args.modes,
              'cases': {}, 'failures': []}
    (args.output / 'manifest.json').write_bytes(args.manifest.read_bytes())
    (args.output / 'harness.py.snapshot').write_bytes(Path(__file__).read_bytes())
    (args.output / 'census.py.snapshot').write_bytes(Path(census.__file__).read_bytes())
    flags = ['--experimental-zero-rc'] if args.ownership == 'opt-in' else []
    prepared = []
    try:
        for case in selected:
            original = census.ROOT / case['source']['path']
            assert census.digest(original) == case['source']['sha256'], 'source identity changed'
            text = original.read_text()
            if 'public_tests' in case:
                text += '\n\nfunc main(out: Stream) -> int:\n'
                text += ''.join('    out.print(' + name + '())\n' for name in case['public_tests'])
                text += '    return 0\n'
            source = args.output / 'sources' / (case['id'] + '.my')
            source.parent.mkdir(exist_ok=True)
            source.write_text(text)
            checked = census.invoke([args.compiler, 'check', source, *flags],
                                    args.output / 'raw' / case['id'] / 'check', env, admitted=True)
            row = {'manifest': case, 'executed_source_sha256': census.digest(source),
                   'source_check': checked, 'modes': {}}
            result['cases'][case['id']] = row
            if checked['exit'] != 0:
                result['failures'].append(case['id'] + '/source-check')
            census.save(args.output / 'results.json', result)
            print(case['id'], 'check', checked['exit'], checked['stderr'].split('\n')[0], flush=True)
            if checked['exit'] is None or checked['exit'] < 0 or (checked['exit'] != 0 and 'error[E_' not in checked['stderr']):
                result['stop_reason'] = 'Compiler/tool failure without source diagnostic'
                return 3
            prepared.append((case, row, source))
        if args.check_only:
            return bool(result['failures'])
        for case, row, source in prepared:
            if row['source_check']['exit'] != 0:
                row['native_not_run_reason'] = 'Source admission refused; no native mode claimed executed.'
                continue
            native = {'id': case['id'], 'source': census.identity(source),
                      'runs': [{'id': '0', 'argv': [], 'stdout': case['expected_stdout'],
                                'exit': case['expected_exit']}], 'modes': args.modes}
            for mode in args.modes:
                lane = census.lane(args, env, native, mode, audit, historical)
                row['modes'][mode] = lane
                if lane['status'] != 'passed':
                    result['failures'].append(case['id'] + '/' + mode)
                census.save(args.output / 'results.json', result)
                print(case['id'], mode, lane['status'], flush=True)
                if lane['status'] in ('build_failed', 'harness_failed'):
                    result['stop_reason'] = 'Compiler/tool failure; later modes remain unmeasured'
                    return 3
    finally:
        lease.close()
        census.save(args.output / 'results.json', result)
    assert census.digest(args.compiler) == result['compiler_sha256'], 'compiler changed during qualification'
    return bool(result['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
