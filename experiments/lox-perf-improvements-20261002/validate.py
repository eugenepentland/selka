#!/usr/bin/env python3
"""Check cross-lane Lox regressions against exact output and unchanged controls."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re


def load_audit():
    path = Path(__file__).resolve().parents[1] / 'lox-performance-audit-20261002/audit.py'
    spec = importlib.util.spec_from_file_location('lox_audit', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--cases', type=Path, default=Path(__file__).with_name('regressions.json'))
    parser.add_argument('--native-gc-stress', action='store_true',
                        help='Both executables must use the native GC runtime')
    args = parser.parse_args()
    audit = load_audit()
    work = args.work.resolve()
    manifest = json.loads((work / 'binaries.json').read_text())
    binaries = {arm: Path(manifest['binaries'][arm])
                for arm in (args.baseline, args.candidate)}
    hashes = {arm: audit.sha(binary) for arm, binary in binaries.items()}
    cases = json.loads(args.cases.read_text())
    inputs = work / 'validation/inputs'
    inputs.mkdir(parents=True, exist_ok=True)
    receipt = {'baseline': args.baseline, 'candidate': args.candidate,
               'binary_sha256': hashes, 'cases_sha256': audit.sha(args.cases),
               'native_gc_stress': args.native_gc_stress, 'samples': []}
    env = audit.clean_env()
    if args.native_gc_stress:
        env['MYLANG_OPTIONS'] = '--gc-stress'
    for case in cases:
        source = inputs / (case['name'] + '.lox')
        source.write_text(case['source'])
        for engine in ('vm', 'tree'):
            for stress in (False, True):
                observations = {}
                for arm, binary in binaries.items():
                    argv = [str(binary), '--engine=' + engine, '--stats']
                    if stress:
                        argv.append('--gc-stress')
                    argv.append(str(source))
                    result = audit.run(argv, env, 60)
                    observations[arm] = {
                        'exit': result['status'],
                        'stdout': result['stdout'].decode(),
                        'stderr': result['stderr'].decode()}
                expected = observations[args.baseline]
                actual = observations[args.candidate]
                stats = re.findall(r'(allocations|collections|freed|live)=(\d+)',
                                   expected['stderr'])
                passed = (expected['exit'] == 0 and len(stats) == 4 and
                          expected['stdout'] == case['stdout'] and actual == expected)
                row = {'case': case['name'], 'engine': engine,
                       'lox_gc_stress': stress, 'source_sha256': audit.sha(source),
                       'expected_stdout': case['stdout'],
                       'observations': observations, 'passed': passed}
                receipt['samples'].append(row)
                audit.save(args.out, receipt)
                if not passed:
                    raise RuntimeError(json.dumps(row, indent=2))
        print('PASS', case['name'], 'VM/tree, normal/stress, exact output and collector work', flush=True)
    for arm, binary in binaries.items():
        if audit.sha(binary) != hashes[arm]:
            raise ValueError('binary changed: ' + arm)
    if audit.sha(args.cases) != receipt['cases_sha256']:
        raise ValueError('regression inputs changed')
    receipt['verified_after'] = True
    audit.save(args.out, receipt)
    print(len(receipt['samples']), 'matched pairs', flush=True)


if __name__ == '__main__':
    main()
