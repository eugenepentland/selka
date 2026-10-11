#!/usr/bin/env python3
"""Stage 2 census, paired slicing counters, and zero-allocation borrow checks."""
import argparse
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
import measure as stage1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'before', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    a = parser.parse_args()
    for name in ('compiler', 'before', 'zig', 'output'):
        setattr(a, name, getattr(a, name).resolve())
    a.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MYLANG_ZIG=str(a.zig), ZIG=str(a.zig), MYL_CORE_LEAKCHECK='1')
    env.pop('MYLANG_COUNTERS', None)
    result = {'schema': 'zero-rc-stage2-v1', 'executions': 0, 'cases': {}, 'focused': {},
              'tools': {name: {'path': str(getattr(a, name)), 'sha256': stage1.digest(getattr(a, name))}
                        for name in ('compiler', 'before', 'zig')}, 'harness_sha256': stage1.digest(__file__)}
    baseline = json.loads((HERE.parent / 'zero-rc-20261011/results.json').read_text())

    def lane(source, compiler, directory, inputs, flags):
        directory.mkdir(parents=True, exist_ok=True)
        binary, llvm = directory / 'program', directory / 'program.ll'
        stage1.command([compiler, 'build', source, '--experimental-zero-rc', '--zig', a.zig,
                        '--cache-dir', a.output / 'cache', '--counters', *flags,
                        '-o', binary, '--emit-llvm', llvm], directory / 'build', env)
        stage1.clean_ir(llvm)
        runs = {}
        for n, expected in inputs.items():
            counts = directory / f'counts-{n}.json'
            stdout = stage1.command([binary, *(['x'] * int(n))], directory / f'run-{n}',
                                    dict(env, MYLANG_COUNTERS=str(counts)))
            if expected is not None:
                assert stdout == expected, (source, n, stdout, expected)
            assert not (directory / f'run-{n}.stderr').read_bytes()
            audit = stage1.audit.audit(counts)
            assert audit['observed_rc_free'] and audit['managed_leak_free'], audit
            summary = stage1.census.summarize(json.loads(counts.read_text()))
            runs[n] = {'stdout': stdout, 'audit': audit, 'kernel': summary['kernel'],
                       'whole_program': summary['whole_program']}
            result['executions'] += 1
        return {'source': str(source.relative_to(ROOT)), 'source_sha256': stage1.digest(source),
                'binary_sha256': stage1.digest(binary), 'llvm_sha256': stage1.digest(llvm), 'runs': runs}

    for name, record in baseline['cases'].items():
        source = ROOT / record['source']
        migrated = HERE / 'migrated' / source.name
        if migrated.exists():
            source = migrated
        answers = {n: run['stdout'] for n, run in record['configs']['release']['runs'].items()}
        configs = {mode: lane(source, a.compiler, a.output / name / mode, answers, flags)
                   for mode, flags in stage1.MODES.items()}
        result['cases'][name] = {'configs': configs}
        stage1.save(a.output / 'partial-results.json', result)
        print('pass', name, flush=True)
    result['census_executions'] = result['executions']
    for kind in ('text', 'bytes'):
        configs = {}
        for mode, flags in stage1.MODES.items():
            before = lane(HERE / f'samples/owned_{kind}.my', a.before,
                          a.output / f'focused-{kind}' / mode / 'before', {'0': None, '9': None}, flags)
            answers = {n: run['stdout'] for n, run in before['runs'].items()}
            after = lane(HERE / f'samples/borrowed_{kind}.my', a.compiler,
                         a.output / f'focused-{kind}' / mode / 'after', answers, flags)
            configs[mode] = {'before': before, 'after': after}
        result['focused'][kind] = configs
        print('pass repeated', kind, flush=True)
    result['borrow_only'] = {}
    for mode, flags in stage1.MODES.items():
        measured = lane(HERE / 'samples/borrow_only.my', a.compiler, a.output / 'borrow-only' / mode,
                        {'0': '0\n', '4': '12000\n', '11': '33000\n'}, flags)
        for run in measured['runs'].values():
            assert run['kernel']['allocs'] == 0 and run['kernel']['reallocs'] == 0, run
        result['borrow_only'][mode] = measured
    result['summary'] = {'supported': len(result['cases']), 'configs': len(stage1.MODES),
                         'census_executions': result['census_executions'], 'total_executions': result['executions'],
                         'allocating_workloads': {n: sum(bool(record['configs']['release']['runs'][n]['kernel']['allocs'] or
                                                              record['configs']['release']['runs'][n]['kernel']['reallocs'])
                                                         for record in result['cases'].values()) for n in ('4', '11')}}
    for entry in result['tools'].values():
        assert stage1.digest(entry['path']) == entry['sha256']
    stage1.save(HERE / 'results.json', result)
    print(json.dumps(result['summary']), flush=True)


if __name__ == '__main__':
    main()
