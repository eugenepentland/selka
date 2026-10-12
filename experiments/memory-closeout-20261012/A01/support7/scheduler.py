#!/usr/bin/env python3
"""Exercise frozen owned scheduler fixture against runtime text emitted by Support7."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

REVISION = 'bed11cf3bf3102ffec44487e431a1573fdf02ad5'
COMPILER_SHA = '540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef'
LEGACY = ('myl_core_retain', 'myl_core_release', 'myl_core_share',
          'count_retain', 'count_release', 'count_is_unique')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(argv, cwd, env, timeout=600):
    try:
        result = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                                capture_output=True, text=True, timeout=timeout)
        return {'argv': list(map(str, argv)), 'status': result.returncode,
                'stdout': result.stdout, 'stderr': result.stderr}
    except subprocess.TimeoutExpired as error:
        def text(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
        return {'argv': list(map(str, argv)), 'status': None, 'timeout': timeout,
                'stdout': text(error.stdout), 'stderr': text(error.stderr)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'source-root', 'runtime-cache', 'output', 'zig'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    assert digest(args.compiler) == COMPILER_SHA
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.source_root,
                                   text=True).strip() == REVISION
    args.output.mkdir(parents=True, exist_ok=False)
    fixture = args.source_root/'src/core/a01_owned_scheduler_fixture.c'
    task_source = (args.source_root/'src/core/runtime/core_tasks.c').read_bytes()
    runtimes = {}
    for path in args.runtime_cache.glob('core_rt-*.c'):
        contents = path.read_bytes()
        if not contents.startswith(b'#define MYL_ZERO_RC 1\n'):
            continue
        assert task_source in contents
        kind = 'counted' if b'void myl_count_dump(' in contents else 'tsan'
        runtimes.setdefault(kind, []).append(path)
    assert all(len(runtimes.get(kind, [])) == 1 for kind in ('counted', 'tsan')), runtimes
    summary = {'source_revision': REVISION, 'compiler_sha256': COMPILER_SHA,
               'fixture_sha256': digest(fixture), 'harness_sha256': digest(__file__),
               'scope': 'Native C-thunk scheduler using exact common compiler-emitted runtime; generated fastcc bridge covered by source map matrix',
               'variants': {}, 'failures': []}
    def save():
        (args.output/'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    for kind in ('counted', 'tsan'):
        directory = args.output/kind
        directory.mkdir()
        runtime = runtimes[kind][0]
        shutil.copyfile(runtime, directory/'core_rt_all.c')
        shutil.copyfile(fixture, directory/'fixture.c')
        binary = directory/'scheduler'
        env = dict(os.environ, ZIG_LOCAL_CACHE_DIR=str(directory/'zig-local'))
        for key in ('MYLANG_CORE_SANITIZE', 'MYLANG_COUNTERS', 'MYLANG_OPTIONS'):
            env.pop(key, None)
        argv = [args.zig, 'cc', '-O2', '-g', '-std=c11', '-pthread', directory/'fixture.c', '-o', binary]
        if kind == 'tsan':
            argv.append('-fsanitize=thread')
        built = run(argv, directory, env)
        item = {'runtime_path': str(runtime), 'runtime_sha256': digest(runtime),
                'build': built, 'runs': []}
        summary['variants'][kind] = item
        if built['status'] != 0 or built['stderr']:
            summary['failures'].append(kind+'/build'); save(); continue
        item['binary_sha256'] = digest(binary)
        symbols = run(['nm', binary], directory, env)
        (directory/'symbols.txt').write_text(symbols['stdout'])
        item['structural_rc_free'] = symbols['status'] == 0 and not any(name in symbols['stdout'] for name in LEGACY)
        if not item['structural_rc_free']:
            summary['failures'].append(kind+'/structural')
        workers = (1, 2, 8) if kind == 'counted' else (8,)
        for threads in workers:
            for mode in ('stress', 'twice', 'lazy'):
                counts = directory/f'counts-{threads}-{mode}.json'
                record = run([binary, mode], directory,
                             dict(env, MYLANG_THREADS=str(threads), MYLANG_COUNTERS=str(counts)), 240)
                record.update(workers=threads, mode=mode)
                if mode == 'twice':
                    record['passed'] = record['status'] == 1 and 'R_TASK_GROUP' in record['stderr'] and 'ThreadSanitizer' not in record['stderr']
                else:
                    expected = ('lazy: no workers\n' if mode == 'lazy' else
                                f'owned tasks: 1010002 submits, binary depth 12, chain 2048, threads {threads}, live 0\n')
                    record['passed'] = record['status'] == 0 and record['stdout'] == expected and record['stderr'] == ''
                    if kind == 'counted':
                        if counts.exists():
                            data = json.loads(counts.read_text()); totals = data['totals']
                            record['counts_sha256'] = digest(counts)
                            record['totals'] = totals
                            required = ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks', 'live_bytes_at_exit')
                            record['passed'] &= all(totals[name] == 0 for name in required)
                        else:
                            record['missing_counts'] = True; record['passed'] = False
                if not record['passed']:
                    summary['failures'].append(f'{kind}/{threads}/{mode}')
                item['runs'].append(record); save()
                print(kind, threads, mode, 'pass' if record['passed'] else 'FAIL', flush=True)
        save()
    raise SystemExit(bool(summary['failures']))


if __name__ == '__main__':
    main()
