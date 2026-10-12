#!/usr/bin/env python3
"""Build immutable application arms with the already-qualified common compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012'
WORK = ROOT / '.tmp/lox-eda-improvements-20261012'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def sources(directory):
    return {str(p.relative_to(directory)): sha(p) for p in sorted(directory.rglob('*'))
            if p.is_file() and (p.suffix == '.my' or p.name == 'mylang.json')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('application', choices=('lox', 'eda'))
    parser.add_argument('--attempt', type=int, default=1)
    args = parser.parse_args()
    app = args.application
    assert os.environ.get('MYLANG_SLOT_DIR')
    suffix = app if args.attempt == 1 else app + '-' + str(args.attempt)
    evidence = HERE / 'build' / suffix
    evidence.mkdir(parents=True, exist_ok=False)
    work = WORK / suffix
    work.mkdir(parents=True, exist_ok=False)
    (work / 'tmp').mkdir()
    common_path = ROOT / 'experiments/text-gaps-20261012/coordinator/common-002/build-receipt.json'
    common = json.loads(common_path.read_text())
    compiler = Path(common['compiler'])
    assert sha(compiler) == common['compiler_sha256']
    for entry in common['installation_files']:
        assert sha(Path(common['installation']) / entry['path']) == entry['sha256']
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert subprocess.run(['git', 'diff', '--quiet', common['source_commit'], head, '--', 'src'], cwd=ROOT).returncode == 0
    assert subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', 'src'], cwd=ROOT).returncode == 0
    if app == 'lox':
        original = work / 'original'
        with (evidence / 'prepare-control.log').open('w') as log:
            subprocess.run([str(OLD / 'lox/prepare-control.sh'), str(original)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        migrated = HERE / 'source/lox'
    else:
        original = OLD / 'eda/original/src'
        migrated = HERE / 'source/eda'
    manifests = {name: {'root': str(path), 'files': sources(path)} for name, path in [('original', original), ('migrated', migrated)]}
    previous_path = ROOT / 'experiments/lox-eda-rerun-20261012/build' / ('lox' if app == 'lox' else 'eda-2') / 'build-receipt.json'
    previous = json.loads(previous_path.read_text())
    assert previous['compiler_sha256'] == common['compiler_sha256']
    assert previous['common_receipt_sha256'] == sha(common_path)
    assert previous['sources']['original']['files'] == manifests['original']['files']
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), MYLANG_JOBS='4',
               MYLANG_COMPONENT_DIR=str(Path(common['installation']) / 'libexec/mylang/components'))
    env.pop('MYLANG_COUNTERS', None)
    env.pop('MYL_CORE_LEAKCHECK', None)
    receipt = {'application': app, 'checkout_commit': head, 'compiler_source_commit': common['source_commit'],
               'compiler': str(compiler), 'compiler_sha256': sha(compiler), 'common_receipt': str(common_path),
               'common_receipt_sha256': sha(common_path), 'sources': manifests, 'binaries': {},
               'build_time_note': 'Elapsed includes admission; this is not a paired compile-time benchmark.'}
    save(evidence / 'build-receipt.json', receipt)
    for name, directory, checked in [('original-rc', original, False), ('migrated-rc', migrated, False), ('zero-rc', migrated, True)]:
        for counted in (False, True):
            arm = name + ('-counted' if counted else '')
            if name == 'original-rc':
                # The original source and complete compiler installation are unchanged.
                # Reuse the pinned control executable; runtime measurements are fresh.
                entry = dict(previous['binaries'][arm])
                assert entry['status'] == 'ok' and sha(entry['path']) == entry['sha256']
                entry['reused_from'] = {'receipt': str(previous_path), 'sha256': sha(previous_path)}
                entry.pop('elapsed_including_admission_s', None)
                receipt['binaries'][arm] = entry
                save(evidence / 'build-receipt.json', receipt)
                print(app, arm, 'reused identical pinned control', flush=True)
                continue
            output = work / arm
            flags = ['--release'] + (['--experimental-zero-rc'] if checked else []) + (['--counters'] if counted else [])
            command = [str(compiler), 'build', str(directory / 'main.my'), *flags,
                       '--cache-dir', str(work / ('cache-' + arm)), '-o', str(output)]
            if checked and not counted:
                command += ['--emit-llvm', str(work / 'zero-rc.ll')]
            start = time.monotonic()
            with (evidence / (arm + '.log')).open('w') as log:
                result = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
            entry = {'command': command, 'flags': flags, 'path': str(output), 'returncode': result.returncode,
                     'source': 'migrated' if directory == migrated else 'original', 'counted': counted,
                     'checked_ownership': checked, 'elapsed_including_admission_s': time.monotonic() - start}
            if result.returncode == 0:
                output.chmod(0o555)
                entry.update(sha256=sha(output), bytes=output.stat().st_size, status='ok')
            else:
                entry['status'] = 'build_failed'
            receipt['binaries'][arm] = entry
            save(evidence / 'build-receipt.json', receipt)
            print(app, arm, entry['status'], flush=True)
    for manifest in manifests.values():
        assert sources(Path(manifest['root'])) == manifest['files']
    assert sha(compiler) == common['compiler_sha256']
    assert all(x['status'] == 'ok' for x in receipt['binaries'].values()), 'build refusals retained in receipt'
    save(HERE / 'build' / (app + '-selected.json'),
         {'path': str(evidence / 'build-receipt.json'), 'sha256': sha(evidence / 'build-receipt.json')})
    print(evidence / 'build-receipt.json', flush=True)


if __name__ == '__main__':
    main()
