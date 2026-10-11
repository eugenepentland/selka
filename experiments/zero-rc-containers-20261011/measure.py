#!/usr/bin/env python3
"""Qualify all 30 census cases and new container cases with whole-program counters."""
import argparse
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
import measure as common


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'before', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'before', 'zig', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MYLANG_ZIG=str(args.zig), ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    env.pop('MYLANG_COUNTERS', None)
    result = {'schema': 'zero-rc-stage3-v1', 'executions': 0, 'cases': {}, 'focused': {},
              'tools': {name: {'path': str(getattr(args, name)), 'sha256': common.digest(getattr(args, name))}
                        for name in ('compiler', 'before', 'zig')}, 'harness_sha256': common.digest(__file__)}
    previous = json.loads((HERE.parent / 'zero-rc-views-20261011/results.json').read_text())
    cases = {}
    for name, record in previous['cases'].items():
        release = record['configs']['release']
        cases[name] = (ROOT / release['source'], {n: run['stdout'] for n, run in release['runs'].items()})
    originals = json.loads((HERE.parent / 'rc-census-20261010/containers.json').read_text())
    for record in originals:
        if record['id'].startswith(('21_', '22_', '23_')):
            source = HERE.parent / 'rc-census-20261010' / record['source']
            migration = HERE / 'migrated' / source.name
            cases[record['id']] = (migration if migration.exists() else source, record['expected'])

    def lane(source, directory, answers, flags, baseline=False):
        directory.mkdir(parents=True, exist_ok=True)
        binary, llvm = directory / 'program', directory / 'program.ll'
        compiler = args.before if baseline else args.compiler
        mode = [] if baseline else ['--experimental-zero-rc']
        common.command([compiler, 'build', source, *mode, '--zig', args.zig,
                        '--cache-dir', args.output / 'cache', '--counters', *flags,
                        '-o', binary, '--emit-llvm', llvm], directory / 'build', env)
        if not baseline:
            common.clean_ir(llvm)
        runs = {}
        for n, expected in answers.items():
            counts = directory / f'counts-{n}.json'
            stdout = common.command([binary, *(['x'] * int(n))], directory / f'run-{n}',
                                    dict(env, MYLANG_COUNTERS=str(counts)))
            assert stdout == expected, (source, n, stdout, expected)
            assert not (directory / f'run-{n}.stderr').read_bytes()
            audit = common.audit.audit(counts)
            assert audit['managed_leak_free'], audit
            if not baseline:
                assert audit['observed_rc_free'], audit
            summary = common.census.summarize(json.loads(counts.read_text()))
            runs[n] = {'stdout': stdout, 'audit': audit, 'kernel': summary['kernel'],
                       'whole_program': summary['whole_program']}
            result['executions'] += 1
        return {'source': str(source.relative_to(ROOT)), 'source_sha256': common.digest(source),
                'binary_sha256': common.digest(binary), 'llvm_sha256': common.digest(llvm), 'runs': runs}

    for name, (source, answers) in sorted(cases.items()):
        configs = {mode: lane(source, args.output / name / mode, answers, flags)
                   for mode, flags in common.MODES.items()}
        result['cases'][name] = {'configs': configs}
        if name.startswith(('21_', '22_', '23_')):
            original = HERE.parent / 'rc-census-20261010/samples' / source.name
            result['cases'][name]['rc_baseline'] = lane(original, args.output / name / 'rc-baseline', answers, ['--release'], True)
        common.save(args.output / 'partial-results.json', result)
        print('pass', name, flush=True)
    for source in sorted((HERE / 'samples').glob('*.my')):
        answer = source.with_suffix('.stdout').read_text()
        result['focused'][source.stem] = {mode: lane(source, args.output / 'focused' / source.stem / mode, {'0': answer}, flags)
                                         for mode, flags in common.MODES.items()}
        common.save(args.output / 'partial-results.json', result)
        print('pass focused', source.stem, flush=True)
    result['summary'] = {'supported': len(result['cases']), 'configs': len(common.MODES),
                         'total_executions': result['executions'], 'focused_cases': len(result['focused']),
                         'allocating_workloads': {n: sum(bool(record['configs']['release']['runs'][n]['kernel']['allocs'] or
                                                              record['configs']['release']['runs'][n]['kernel']['reallocs'])
                                                         for record in result['cases'].values()) for n in ('4', '11')}}
    for record in result['tools'].values():
        assert common.digest(record['path']) == record['sha256']
    common.save(HERE / 'results.json', result)
    print(json.dumps(result['summary']), flush=True)


if __name__ == '__main__':
    main()
