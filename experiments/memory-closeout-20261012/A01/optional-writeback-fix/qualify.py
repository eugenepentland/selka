#!/usr/bin/env python3
"""Persist one native cleanup proof and the three original reduced controls."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reducers', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    archive = HERE/'raw'/args.output.name
    archive.mkdir(exist_ok=False)
    compiler = args.compiler.resolve()
    env = dict(os.environ)
    for key in ('MYLANG_COUNTERS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)

    def run(name, command, environment=env):
        result = subprocess.run(list(map(str, command)), env=environment, cwd=ROOT,
                                capture_output=True, text=True, timeout=600)
        for kind in ('stdout', 'stderr'):
            (args.output/(name+'.'+kind)).write_text(getattr(result, kind))
            (archive/(name+'.'+kind)).write_text(getattr(result, kind))
        return {'argv': list(map(str, command)), 'exit': result.returncode,
                'stdout': name+'.stdout', 'stderr': name+'.stderr'}

    result = {'base': '50ac68c1f695f5f2cc461b55c44a99e5e59a2a90',
              'compiler': str(compiler), 'compiler_sha256': digest(compiler),
              'source_sha256': digest(HERE/'main.my'), 'checks': {}, 'passed': True}
    for name in ('owned-option', 'copied-option', 'scalar-option-control'):
        source = args.reducers/(name+'.my')
        check = run(name, [compiler, 'check', source, '--experimental-zero-rc', '--no-cache'])
        check['source_sha256'] = digest(source)
        result['checks'][name] = check
        result['passed'] &= check['exit'] == 0
    negative = run('narrowed-mut', [compiler, 'check', HERE/'narrowed-mut.my', '--experimental-zero-rc', '--no-cache'])
    result['negative'] = negative
    result['passed'] &= negative['exit'] == 1 and 'E_SINGLE_OWNER_BORROW' in (args.output/'narrowed-mut.stderr').read_text()
    binary = args.output/'program'
    llvm = args.output/'program.ll'
    result['build'] = run('build', [compiler, 'build', HERE/'main.my', '--release', '--verify-facts',
                                  '--counters', '--experimental-zero-rc', '--emit-llvm', llvm,
                                  '--cache-dir', args.output/'cache', '-o', binary])
    result['passed'] &= result['build']['exit'] == 0
    if result['build']['exit'] == 0:
        counts = args.output/'counts.json'
        result['run'] = run('run', [binary], dict(env, MYLANG_COUNTERS=str(counts)))
        result['passed'] &= result['run']['exit'] == 0 and (args.output/'run.stdout').read_text() == 'optional-writeback 42\n'
        result['passed'] &= (args.output/'run.stderr').read_text() == ''
        audit = runpy.run_path(str(ROOT/'experiments/zero-rc-20261011/audit.py'))['audit']
        result['counters'] = audit(counts)
        result['passed'] &= result['counters']['observed_rc_free'] and result['counters']['managed_leak_free']
        result['binary_sha256'] = digest(binary)
        result['symbols'] = run('symbols', ['nm', binary])
        symbols = (args.output/'symbols.stdout').read_text()
        legacy = ('myl_core_retain', 'myl_core_release', 'myl_core_share', 'count_retain', 'count_release', 'count_is_unique')
        result['legacy_symbols'] = [name for name in legacy if name in symbols]
        result['passed'] &= result['symbols']['exit'] == 0 and not result['legacy_symbols']
        result['ir'] = run('ir', [compiler, 'dump-ir', HERE/'main.my', '--experimental-zero-rc'])
        result['union_take_occurrences'] = (args.output/'ir.stdout').read_text().count('union_take')
        result['passed'] &= result['ir']['exit'] == 0 and result['union_take_occurrences'] > 0
        for path in (llvm, counts, args.output/'ir.stdout', args.output/'symbols.stdout'):
            with gzip.open(archive/(path.name+'.gz'), 'wb') as output:
                output.write(path.read_bytes())
    (args.output/'results.json').write_text(json.dumps(result, indent=2)+'\n')
    (archive/'results.json').write_text(json.dumps(result, indent=2)+'\n')
    print('optional writeback', 'PASS' if result['passed'] else 'FAIL', flush=True)
    raise SystemExit(not result['passed'])


if __name__ == '__main__':
    main()
