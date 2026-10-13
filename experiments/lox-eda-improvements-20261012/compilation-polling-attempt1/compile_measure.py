#!/usr/bin/env python3
"""Three paired cold/warm guest-build observations under one timing lease per pair."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from receipts import build_path, validate_build

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pair(application, number):
    selected = build_path(application)
    build = validate_build(selected)
    previous = ROOT / 'experiments/lox-eda-rerun-20261012/build' / ('lox' if application == 'lox' else 'eda-2') / 'build-receipt.json'
    baseline = json.loads(previous.read_text())
    assert build['compiler_sha256'] == baseline['compiler_sha256'] == sha(build['compiler'])
    assert build['common_receipt_sha256'] == baseline['common_receipt_sha256'] == sha(build['common_receipt'])
    compiler = build['compiler']
    sources = {'before': baseline['sources']['migrated'], 'after': build['sources']['migrated']}
    dest = HERE / 'compilation' / application / str(number)
    work = ROOT / '.tmp/lox-eda-improvements-20261012/compilation' / application / str(number)
    dest.mkdir(parents=True, exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, TMPDIR=str(work), MYLANG_JOBS='4')
    env.pop('MYLANG_COUNTERS', None)
    env.pop('MYL_CORE_LEAKCHECK', None)
    common = json.loads(Path(build['common_receipt']).read_text())
    env['MYLANG_COMPONENT_DIR'] = str(Path(common['installation']) / 'libexec/mylang/components')
    rows = []
    for label in (('before', 'after') if number % 2 == 0 else ('after', 'before')):
        source = sources[label]
        for name, identity in source['files'].items():
            assert sha(Path(source['root']) / name) == identity
        cache = work / ('cache-' + label)
        binary = work / label
        for state in ('cold-guest-cache', 'warm-guest-cache'):
            usage = dest / (label + '-' + state + '.usage')
            command = [compiler, 'build', str(Path(source['root']) / 'main.my'),
                       '--release', '--experimental-zero-rc', '--cache-dir', str(cache), '-o', str(binary)]
            started = time.monotonic()
            with (dest / (label + '-' + state + '.stdout')).open('w') as out, (dest / (label + '-' + state + '.stderr')).open('w') as err:
                process = subprocess.Popen(['/usr/bin/time', '-f', '%e %M', '-o', str(usage), *command],
                                           cwd=ROOT, env=env, stdout=out, stderr=err, start_new_session=True)
                status = 'ok'
                try:
                    returncode = process.wait(timeout=600)
                    if returncode != 0:
                        status = 'failed'
                except subprocess.TimeoutExpired:
                    import signal
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    returncode = process.wait()
                    status = 'timeout'
            elapsed = time.monotonic() - started
            if status != 'ok':
                rows.append({'arm': label, 'cache_state': state, 'command': command, 'status': status,
                             'returncode': returncode, 'elapsed_seconds': elapsed, 'absolute_ceiling_seconds': 600})
                (dest / 'progress.json').write_text(json.dumps(rows, indent=2) + '\n')
                raise RuntimeError((application, label, state, status))
            seconds, rss = usage.read_text().split()
            rows.append({'arm': label, 'cache_state': state, 'command': command,
                         'elapsed_seconds': elapsed, 'gnu_time_seconds': float(seconds),
                         'gnu_time_maxrss_kib': int(rss), 'binary_sha256': sha(binary)})
            (dest / 'progress.json').write_text(json.dumps(rows, indent=2) + '\n')
        # Only this pair's disposable guest cache is removed to bound disk use.
        shutil.rmtree(cache)
        for name, identity in source['files'].items():
            assert sha(Path(source['root']) / name) == identity
    result = {'application': application, 'pair': number, 'samples': rows,
              'build_receipt': str(selected), 'build_receipt_sha256': sha(selected),
              'compiler_sha256': sha(compiler), 'source_manifests': sources,
              'affinity': sorted(os.sched_getaffinity(0)), 'loadavg_end': os.getloadavg(),
              'method': 'Fresh private guest caches followed by warm replay; OS and shared host-tool caches are not flushed. Admission wait excluded.',
              'rss_limit': 'GNU time maxrss for the build command; not summed concurrent process-tree/cgroup peak RSS.'}
    (dest / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(application, number, [(r['arm'], r['cache_state'], round(r['elapsed_seconds'], 3)) for r in rows], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--application', choices=('lox', 'eda'))
    parser.add_argument('--pair', type=int, choices=range(3))
    parser.add_argument('--admitted', action='store_true')
    args = parser.parse_args()
    if args.admitted:
        assert args.application is not None and args.pair is not None
        pair(args.application, args.pair)
        return
    assert os.environ.get('MYLANG_SLOT_DIR')
    for application in ('lox', 'eda'):
        for number in range(3):
            subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'timing', sys.executable,
                            '-B', str(Path(__file__).resolve()), '--admitted',
                            '--application', application, '--pair', str(number)], check=True, cwd=ROOT)


if __name__ == '__main__':
    main()
