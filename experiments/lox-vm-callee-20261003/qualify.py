#!/usr/bin/env python3
"""Run every public Lox test freshly under both backends and GC stress.

Each module has private cache/output paths. The driver module also uses its
explicit Clock provider fixtures. Native GC stress is a separate runtime;
normal runs use the CLI's default checked RC runtime.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--expected-count', type=int, default=83)
    args = parser.parse_args()
    expected_count = args.expected_count
    source, compiler, work = (p.resolve() for p in
                              (args.source, args.compiler, args.work))
    root = Path(__file__).resolve().parents[2]
    wrapper = root / 'scripts/build-slot.sh'
    work.mkdir(parents=True, exist_ok=True)
    (work / 'tmp').mkdir(exist_ok=True)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(work / 'tmp')
    modules = sorted(source.glob('*_test.my')) + [source / 'driver_tests.my']
    expected = []
    for module in modules:
        text = module.read_text()
        name = re.search(r'^module (\w+)', text).group(1)
        expected.extend(name + '::' + test for test in re.findall(
            r'^public def (test_\w+)\(', text, flags=re.M))
    assert len(expected) == len(set(expected)) == expected_count, expected
    source_hashes = {str(p.relative_to(source)): sha(p) for p in sorted(source.rglob('*')) if p.is_file()}
    start = {'started_utc': now(), 'source': str(source),
             'compiler': str(compiler), 'compiler_sha256': sha(compiler),
             'source_hashes': source_hashes,
             'fixture_sha256': sha(source / 'driver_cases.json'),
             'expected': expected}
    save(work / 'start.json', start)

    def qualify(backend, stress):
        tag = backend + ('-stress' if stress else '-normal')
        out = work / tag
        out.mkdir(exist_ok=True)
        rows = []
        for module in modules:
            argv = [str(wrapper), 'build', str(compiler), 'test', str(module),
                    '--force', '--max-steps', '1000000000', '--timeout-ms',
                    '180000', '--jobs', '1', '--cache-dir', str(out / 'cache'),
                    '--json']
            argv += ['--release'] if backend == 'llvm' else ['--mode', 'Debug']
            if stress:
                argv += ['--gc-stress']
            if module.name == 'driver_tests.my':
                argv += ['--cases', str(source / 'driver_cases.json')]
            row = {'module': module.name, 'argv': argv, 'cwd': str(root),
                   'env': {'TMPDIR': env['TMPDIR']}, 'started_utc': now()}
            stdout_path = out / (module.stem + '.json')
            with stdout_path.open('wb') as stdout, (out / (
                    module.stem + '.log')).open('wb') as stderr:
                status = subprocess.run(argv, cwd=root, env=env, stdout=stdout,
                                        stderr=stderr, timeout=900).returncode
            row.update(status=status, finished_utc=now(),
                       stdout_sha256=sha(stdout_path))
            doc = json.loads(stdout_path.read_bytes())
            row['summary'] = {key: doc.get(key, 0) for key in
                              ['passed', 'failed', 'skipped', 'cached', 'executed']}
            row['tests'] = [{key: test[key] for key in ['name', 'status']}
                            for test in doc['tests']]
            rows.append(row)
            save(out / 'commands.json', rows)
            print(tag, module.name, 'status', status, row['summary'], flush=True)
        names = [test['name'] for row in rows for test in row['tests']]
        totals = {key: sum(row['summary'][key] for row in rows) for key in
                  ['passed', 'failed', 'skipped', 'cached', 'executed']}
        summary = {'flavor': tag,
                   'runtime': 'tracing GC stress' if stress else 'default checked RC',
                   'totals': totals, 'expected_count': len(expected),
                   'actual_count': len(names),
                   'missing': sorted(set(expected) - set(names)),
                   'unexpected': sorted(set(names) - set(expected)),
                   'all_status_passed': all(test['status'] == 'passed' for row in
                                            rows for test in row['tests']),
                   'all_exit_zero': all(row['status'] == 0 for row in rows)}
        save(out / 'summary.json', summary)
        assert totals == {'passed': expected_count, 'failed': 0, 'skipped': 0,
                          'cached': 0, 'executed': expected_count}, summary
        assert len(names) == len(set(names)) == expected_count, summary
        assert set(expected) == set(names), summary
        assert summary['all_status_passed'] and summary['all_exit_zero'], summary
        return summary

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(qualify, backend, stress): (backend, stress)
                   for backend in ['qbe', 'llvm'] for stress in [False, True]}
        for future in concurrent.futures.as_completed(futures):
            try:
                results.append(future.result())
            except Exception as error:
                results.append({'flavor': futures[future], 'error': repr(error)})
            save(work / 'suite-summary.json', results)
    assert {str(p.relative_to(source)): sha(p) for p in sorted(source.rglob('*')) if p.is_file()} == source_hashes
    assert sha(source / 'driver_cases.json') == start['fixture_sha256']
    assert sha(compiler) == start['compiler_sha256']
    assert len(results) == 4 and not any('error' in r for r in results), results
    save(work / 'completed.json', {'finished_utc': now(),
         'source_unchanged': True, 'compiler_unchanged': True,
         'fresh_passes': sum(r['totals']['passed'] for r in results),
         'results': results})


if __name__ == '__main__':
    main()
