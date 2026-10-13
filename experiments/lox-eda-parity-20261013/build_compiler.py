#!/usr/bin/env python3
"""Build one frozen compiler installation using the previously qualified seed route."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def sources():
    paths = [*ROOT.glob('*.zig'), ROOT / 'build.zig.zon', ROOT / '.zigversion',
             ROOT / 'guardian.toml', *ROOT.joinpath('src').rglob('*'),
             *ROOT.joinpath('selfhost').rglob('*')]
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(set(paths)) if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attempt')
    args = parser.parse_args()
    assert args.attempt and '/' not in args.attempt and args.attempt not in ('.', '..')
    assert os.environ.get('MYLANG_SLOT_DIR') and os.environ.get('ZIG')
    scope = ['src', 'selfhost', 'build.zig', 'build.zig.zon', 'guardian.toml']
    assert not subprocess.check_output(['git', 'diff', '--name-only', 'HEAD', '--', *scope], cwd=ROOT)
    assert not subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *scope], cwd=ROOT)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    inputs = sources()
    route_path = ROOT / 'experiments/text-gaps-20261012/coordinator/component-route.json'
    route = json.loads(route_path.read_text())
    for entry in route['qualified_inputs']:
        assert sha(entry['path']) == entry['sha256']
    archive = next(x['path'] for x in route['qualified_inputs'] if x['path'].endswith('.tar'))
    pin = next(x['path'] for x in route['qualified_inputs'] if x['path'].endswith('.json'))
    evidence = HERE / 'coordinator' / args.attempt
    work = ROOT / '.tmp/lox-eda-parity/coordinator' / args.attempt
    evidence.mkdir(parents=True, exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    install = work / 'install'
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), MYLANG_JOBS='4')
    Path(env['TMPDIR']).mkdir()
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', env['ZIG'], 'build',
               '-p', str(install), '--cache-dir', str(work / 'zig-cache'),
               '-j' + env['MYLANG_DEV_JOBS'], '--maxrss', env['MYLANG_DEV_MAXRSS'],
               '-Dcomponent-owned-compiler-pin=' + pin, '-Dcomponent-seed-source=' + archive]
    before = {'source_commit': commit, 'source_files': inputs, 'command': command,
              'build_harness': str(Path(__file__).resolve()), 'build_harness_sha256': sha(__file__),
              'zig': env['ZIG'], 'zig_sha256': sha(env['ZIG']),
              'component_route': str(route_path), 'component_route_sha256': sha(route_path),
              'qualified_component_inputs': route['qualified_inputs'],
              'guardian_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT.parent / 'guardian-zig', text=True).strip()}
    save(evidence / 'inputs.json', before)
    with (evidence / 'build.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    save(evidence / 'status.json', {'returncode': result.returncode})
    assert result.returncode == 0
    assert sources() == inputs, 'compiler inputs changed during build'
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == commit
    compiler = install / 'bin/mylang'
    files = [{'path': str(path.relative_to(install)), 'sha256': sha(path), 'bytes': path.stat().st_size}
             for path in sorted(install.rglob('*')) if path.is_file()]
    for entry in files:
        path = install / entry['path']
        path.chmod(path.stat().st_mode & ~0o222)
    save(evidence / 'build-receipt.json', {
        'source_commit': commit, 'compiler': str(compiler), 'compiler_sha256': sha(compiler),
        'installation': str(install), 'installation_files': files,
        'inputs': str(evidence / 'inputs.json'), 'inputs_sha256': sha(evidence / 'inputs.json'),
        'build_command': command, 'qualification': 'Build and Guardian passed; application and complete registered qualification remain separate.',
        'compile_time_note': 'Admission-inclusive build log is not a compiler performance sample.'})
    print(evidence / 'build-receipt.json', flush=True)


if __name__ == '__main__':
    main()
