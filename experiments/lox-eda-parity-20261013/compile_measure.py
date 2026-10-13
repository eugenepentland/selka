#!/usr/bin/env python3
"""Compare private cold/warm guest builds, excluding timing-admission wait."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def validate(receipt):
    value = json.loads(receipt.read_text())
    assert sha(value['compiler']) == value['compiler_sha256']
    assert sha(value['common_receipt']) == value['common_receipt_sha256']
    common = json.loads(Path(value['common_receipt']).read_text())
    assert common['compiler_sha256'] == value['compiler_sha256']
    for entry in common['installation_files']:
        assert sha(Path(common['installation']) / entry['path']) == entry['sha256']
    source = value['sources']['migrated']
    for name, digest in source['files'].items():
        assert sha(Path(source['root']) / name) == digest
    return value, common


def observe(args):
    current, current_common = validate(args.build)
    previous, previous_common = validate(args.previous_build)
    app = current['application']
    assert previous['application'] == app
    destination = HERE / 'attempts' / args.attempt / 'compilation' / app / str(args.pair)
    work = args.root / '.tmp/lox-eda-parity/compilation' / args.attempt / app / str(args.pair)
    destination.mkdir(parents=True, exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    arms = {
        'before': (previous, previous_common, previous['sources']['migrated']),
        'before-same-compiler': (current, current_common, previous['sources']['migrated']),
        'after': (current, current_common, current['sources']['migrated']),
    }
    result = {
        'application': app, 'pair': args.pair, 'samples': [],
        'receipts': {str(p): sha(p) for p in (args.build, args.previous_build)},
        'harness_sha256': sha(__file__),
        'source_manifests': {name: entry[2] for name, entry in arms.items()},
        'compiler_sha256': {name: entry[0]['compiler_sha256'] for name, entry in arms.items()},
        'affinity': sorted(os.sched_getaffinity(0)), 'loadavg_start': os.getloadavg(),
        'method': 'Three alternating observations. Fresh private guest caches followed by warm replay; OS/shared host-tool caches are not flushed. Admission wait excluded. Instrumentation disabled.',
        'rss_limit': 'GNU time maximum RSS for the build command and its waited children, not a summed concurrent process-tree or cgroup peak.',
    }
    order = list(arms) if args.pair % 2 == 0 else list(reversed(arms))
    for name in order:
        build, common, source = arms[name]
        cache = work / ('cache-' + name)
        binary = work / name
        environment = dict(os.environ, TMPDIR=str(work), MYLANG_JOBS='4',
                           MYLANG_COMPONENT_DIR=str(Path(common['installation']) / 'libexec/mylang/components'))
        environment.pop('MYLANG_COUNTERS', None)
        environment.pop('MYL_CORE_LEAKCHECK', None)
        for state in ('cold-guest-cache', 'warm-guest-cache'):
            validate(args.build)
            validate(args.previous_build)
            command = [build['compiler'], 'build', str(Path(source['root']) / 'main.my'),
                       '--release', '--experimental-zero-rc', '--cache-dir', str(cache), '-o', str(binary)]
            stem = name + '-' + state
            usage = destination / (stem + '.usage')
            started = time.perf_counter()
            with (destination / (stem + '.stdout')).open('w') as out, (destination / (stem + '.stderr')).open('w') as err:
                process = subprocess.Popen(['/usr/bin/time', '-f', '%e %M', '-o', str(usage), *command],
                                           cwd=args.root, env=environment, stdout=out, stderr=err, start_new_session=True)
                expired = threading.Event()

                def expire():
                    expired.set()
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

                deadline = threading.Timer(600, expire)
                deadline.daemon = True
                deadline.start()
                try:
                    code = process.wait()
                finally:
                    deadline.cancel()
                    deadline.join()
            row = {'arm': name, 'cache_state': state, 'command': command,
                   'elapsed_seconds': time.perf_counter() - started, 'returncode': code,
                   'status': 'timeout' if expired.is_set() else ('ok' if code == 0 else 'failed'),
                   'absolute_ceiling_seconds': 600}
            if row['status'] == 'ok':
                seconds, rss = usage.read_text().split()
                row.update(gnu_time_seconds=float(seconds), gnu_time_maxrss_kib=int(rss), binary_sha256=sha(binary))
            result['samples'].append(row)
            save(destination / 'progress.json', result)
            assert row['status'] == 'ok', (app, name, state, row['status'])
    validate(args.build)
    validate(args.previous_build)
    result['loadavg_end'] = os.getloadavg()
    save(destination / 'results.json', result)
    print(json.dumps({'application': app, 'pair': args.pair,
                      'samples': [{key: row[key] for key in ('arm', 'cache_state', 'elapsed_seconds', 'gnu_time_maxrss_kib')}
                                  for row in result['samples']]}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'build', 'previous-build'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--attempt', required=True)
    parser.add_argument('--pair', type=int, choices=range(3), required=True)
    parser.add_argument('--admitted', action='store_true')
    args = parser.parse_args()
    args.root = args.root.resolve()
    if args.admitted:
        observe(args)
    else:
        assert os.environ.get('MYLANG_SLOT_DIR')
        subprocess.run([str(args.root / 'scripts/build-slot.sh'), 'timing', sys.executable,
                        '-B', str(Path(__file__).resolve()), *sys.argv[1:], '--admitted'],
                       cwd=args.root, check=True)


if __name__ == '__main__':
    main()
