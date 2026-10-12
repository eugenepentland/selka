#!/usr/bin/env python3
"""Qualify both optimized applications in the five required ownership modes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from receipts import build_path, qualified, validate_build

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MODES = {'verified-release': ['--release', '--verify-facts'], 'release': ['--release'], 'debug': ['--unoptimized'],
         'optimized-debug': ['--optimize-debug'], 'no-facts': ['--release', '--no-facts']}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('application', choices=('lox', 'eda'))
    args = parser.parse_args()
    assert os.environ.get('MYLANG_SLOT_DIR')
    app = args.application
    manifest_path = build_path(app)
    build = validate_build(manifest_path)
    qualified(app, manifest_path)
    compiler = build['compiler']
    assert sha(compiler) == build['compiler_sha256']
    source = build['sources']['migrated']
    for name, identity in source['files'].items():
        assert sha(Path(source['root']) / name) == identity
    dest = HERE / 'matrix' / app
    work = ROOT / '.tmp/lox-eda-improvements-20261012/matrix' / app
    dest.mkdir(parents=True, exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    common = json.loads(Path(build['common_receipt']).read_text())
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1', TMPDIR=str(work), MYLANG_JOBS='4',
               MYLANG_COMPONENT_DIR=str(Path(common['installation']) / 'libexec/mylang/components'))
    verified = HERE / 'qualification' / app / 'checked-tests.stdout'
    rows = {}
    def run(label, command, expected=None, minimum=None):
        with (dest / (label + '.stdout')).open('w') as out, (dest / (label + '.stderr')).open('w') as err:
            result = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command],
                                    cwd=ROOT, env=env, stdout=out, stderr=err)
        row = {'command': command, 'returncode': result.returncode}
        if result.returncode == 0 and (expected is not None or minimum is not None):
            row['result'] = json.loads((dest / (label + '.stdout')).read_text())
        rows[label] = row
        (dest / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
        assert result.returncode == 0, (app, label)
        if 'result' in row:
            value = row['result']
            assert all(value[key] == 0 for key in ('failed', 'skipped', 'unsupported'))
            assert value['passed'] == expected if expected is not None else value['passed'] >= minimum
        print(app, label, 'passed', flush=True)
    providers = {}
    if app == 'lox':
        previous_path = ROOT / 'experiments/lox-eda-rerun-20261012/build/lox/build-receipt.json'
        previous = json.loads(previous_path.read_text())['binaries']['zero-rc']
        assert sha(previous['path']) == previous['sha256']
        providers = {str(Path(source['root']) / 'driver_cases.json'): sha(Path(source['root']) / 'driver_cases.json'),
                     str(HERE / 'P2/cases.json'): sha(HERE / 'P2/cases.json'),
                     str(HERE / 'P1/verify.py'): sha(HERE / 'P1/verify.py')}
        (dest / 'provider-inputs.json').write_text(json.dumps(providers, indent=2) + '\n')
    for mode, flags in MODES.items():
        options = ['--experimental-zero-rc', *flags,
                   '--jobs', '4', '--max-steps', '1000000000', '--max-frames', '40000',
                   '--max-memory', '2G', '--timeout-ms', '120000',
                   '--cache-dir', str(work / mode / 'tests'), '--json']
        if mode == 'verified-release':
            rows[mode + '-units'] = {'reused_qualification': str(verified), 'sha256': sha(verified),
                                    'result': json.loads(verified.read_text())}
        else:
            run(mode + '-units', [compiler, 'test', source['root'], *options], minimum=65 if app == 'lox' else 310)
        if app == 'lox':
            for name, cases, count in [('driver', Path(source['root']) / 'driver_cases.json', 13),
                                       ('p2_tree', HERE / 'P2/cases.json', 6)]:
                run(mode + '-' + name, [compiler, 'test', str(Path(source['root']) / (name + '_tests.my')),
                                       '--cases', str(cases), *options], expected=count)
            binary = Path(build['binaries']['zero-rc']['path']) if mode == 'release' else work / (mode + '-lox')
            if mode != 'release':
                run(mode + '-build', [compiler, 'build', str(Path(source['root']) / 'main.my'),
                    '--experimental-zero-rc', *flags, '--cache-dir', str(work / mode / 'build'), '-o', str(binary)])
            run(mode + '-vm-regressions', [sys.executable, '-B', str(HERE / 'P1/verify.py'), str(binary),
                previous['path'], str(work / (mode + '-vm-cases')), '--correctness-only'])
    for path, identity in providers.items():
        assert sha(path) == identity
    validate_build(manifest_path)
    qualified(app, manifest_path)
    (dest / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
    print('PASS', app, 'all five checked ownership modes', flush=True)


if __name__ == '__main__':
    main()
