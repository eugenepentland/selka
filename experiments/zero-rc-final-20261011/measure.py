#!/usr/bin/env python3
"""Requalify the complete zero-RC census, views, containers and resource fixtures."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
import measure as common

def clean_ir(path):
    text = path.read_text()
    assert '; mylang-zero-rc-v2' in text
    for line in text.splitlines():
        assert 'load atomic i32' not in line, line
        assert not ('store i32' in line and '!tbaa !3' in line), line
        assert not any(name in line for name in ('@myl_core_retain', '@myl_core_release', '@myl_core_share(', '@myl_core_free_block(')), line

def sources():
    previous = json.loads((HERE.parent / 'zero-rc-containers-20261011/results.json').read_text())
    for name, record in previous['cases'].items():
        release = record['configs']['release']
        yield 'census/' + name, ROOT / release['source'], {n: r['stdout'] for n, r in release['runs'].items()}
    for family in ('zero-rc-containers-20261011', 'zero-rc-resources-20261011', HERE.name):
        for path in sorted((HERE.parent / family / 'samples').glob('*.my')):
            yield family + '/' + path.stem, path, {'0': path.with_suffix('.stdout').read_text()}
    views = json.loads((HERE.parent / 'zero-rc-views-20261011/results.json').read_text())
    borrow = views['borrow_only']['release']
    yield 'views/borrow_only', ROOT / borrow['source'], {n: r['stdout'] for n, r in borrow['runs'].items()}
    for name, record in views['focused'].items():
        borrowed = record['release']['after']
        yield 'views/' + name, ROOT / borrowed['source'], {n: r['stdout'] for n, r in borrowed['runs'].items()}

def lane(args, env, source, answers, name, mode, flags):
    directory = args.output / name / mode
    directory.mkdir(parents=True, exist_ok=True)
    binary, llvm = directory / 'program', directory / 'program.ll'
    linked = source.with_suffix('.c')
    common.command([args.compiler, 'build', source, '--experimental-zero-rc', '--zig', args.zig,
                    '--cache-dir', args.output / 'cache', '--counters', *flags,
                    *(['--link', linked] if linked.exists() else []), '-o', binary, '--emit-llvm', llvm], directory / 'build', env)
    clean_ir(llvm)
    symbols = subprocess.run(['nm', binary], capture_output=True, text=True, check=True).stdout
    assert not any(name in symbols for name in ('myl_core_retain', 'myl_core_release', 'myl_core_share')), binary
    runs = {}
    for count, expected in answers.items():
        counters = directory / ('counts-' + count + '.json')
        stdout = common.command([binary, *(['x'] * int(count))], directory / ('run-' + count), dict(env, MYLANG_COUNTERS=str(counters)))
        assert stdout == expected, (source, count, stdout, expected)
        assert not (directory / ('run-' + count + '.stderr')).read_bytes()
        audit = common.audit.audit(counters)
        assert audit['observed_rc_free'] and audit['managed_leak_free'], audit
        summary = common.census.summarize(json.loads(counters.read_text()))
        runs[count] = {'stdout': stdout, 'audit': audit, 'kernel': summary['kernel'], 'whole_program': summary['whole_program']}
    return {'source': str(source.relative_to(ROOT)), 'source_sha256': common.digest(source),
            'binary_sha256': common.digest(binary), 'llvm_sha256': common.digest(llvm), 'runs': runs}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'zig', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS'):
        env.pop(name, None)
    result = {'schema': 'zero-rc-final-v1', 'tools': {n: {'path': str(getattr(args, n)), 'sha256': common.digest(getattr(args, n))} for n in ('compiler', 'zig')},
              'harness_sha256': common.digest(__file__), 'cases': {}}
    for name, source, answers in sources():
        result['cases'][name] = {mode: lane(args, env, source, answers, name, mode, flags) for mode, flags in common.MODES.items()}
        common.save(args.output / 'partial-results.json', result)
        print('pass', name, flush=True)
    result['summary'] = {'samples': len(result['cases']), 'executions': sum(len(lane['runs']) for modes in result['cases'].values() for lane in modes.values()),
                         'census': sum(n.startswith('census/') for n in result['cases']),
                         'allocating_workloads': {count: sum(bool(modes['release']['runs'][count]['kernel']['allocs'] or modes['release']['runs'][count]['kernel']['reallocs'])
                                                            for name, modes in result['cases'].items() if name.startswith('census/')) for count in ('4', '11')}}
    for record in result['tools'].values():
        assert common.digest(record['path']) == record['sha256']
    common.save(HERE / 'results.json', result)
    print(json.dumps(result['summary']), flush=True)
if __name__ == '__main__':
    main()
