#!/usr/bin/env python3
"""Freeze a common compiler installation and build unchanged text benchmarks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASELINE = ROOT / '.tmp/micro-gaps/coordinator/install'
SOURCE = ROOT / 'experiments/micro-ownership-20261012/expanded/migrated/text.my'
EXPECTED_SOURCE = '71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def run(command, log, env=None):
    with log.open('w') as stream:
        subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                       stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    args = parser.parse_args()
    assert args.name and '/' not in args.name and args.name not in ('.', '..')
    assert os.environ.get('MYLANG_SLOT_DIR')
    assert sha(SOURCE) == EXPECTED_SOURCE
    assert not subprocess.check_output(['git', 'diff', '--name-only', 'HEAD', '--', 'src'], cwd=ROOT)
    assert not subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', 'src'], cwd=ROOT)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    evidence = HERE / args.name
    work = ROOT / '.tmp/text-gaps/coordinator' / args.name
    evidence.mkdir(exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), MYLANG_JOBS='4')
    Path(env['TMPDIR']).mkdir()
    build = [str(ROOT / 'scripts/build-slot.sh'), 'build', env['ZIG'], 'build',
             'seed-compiler', '-p', str(work / 'host'), '-j' + env['MYLANG_DEV_JOBS'],
             '--maxrss', env['MYLANG_DEV_MAXRSS']]
    run(build, evidence / 'host-build.log', env)
    install = work / 'install'
    shutil.copytree(BASELINE, install, symlinks=True)
    compiler = install / 'bin/mylang'
    assert not compiler.is_symlink()
    compiler.chmod(0o755)
    shutil.copy2(work / 'host/focus/mylang', compiler)
    compiler.chmod(0o555)
    compiler_hash = sha(compiler)
    env['MYLANG_COMPONENT_DIR'] = str(install / 'libexec/mylang/components')
    entries = []
    for kind in ('runtime', 'counted'):
        binary = work / ('text-' + kind)
        command = [str(compiler), 'build', str(SOURCE), '--release', '--experimental-zero-rc',
                   '--cache-dir', str(work / ('cache-' + kind)), '-o', str(binary),
                   '--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c')]
        if kind == 'counted':
            command.append('--counters')
        run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command], evidence / (kind + '-build.log'), env)
        binary.chmod(0o555)
        entries.append({'kind': kind, 'binary': str(binary), 'sha256': sha(binary),
                        'source': str(SOURCE), 'source_sha256': sha(SOURCE),
                        'command': command, 'flags': command[3:], 'status': 'ok'})
        run([str(ROOT / 'scripts/build-slot.sh'), 'build', 'python3', '-B',
             str(ROOT / 'experiments/text-gaps-20261012/split/qualify.py'), str(binary),
             str(evidence / (kind + '-qualification'))], evidence / (kind + '-qualification.log'), env)
        result = json.loads((evidence / (kind + '-qualification/qualification.json')).read_text())
        assert result['all_ok'] and len(result['results']) == 50
        if kind == 'counted':
            assert all(row['counters'] is not None for row in result['results'])
    assert sha(compiler) == compiler_hash and sha(SOURCE) == EXPECTED_SOURCE
    assert not subprocess.check_output(['git', 'diff', '--name-only', 'HEAD', '--', 'src'], cwd=ROOT)
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == commit
    files = [{'path': str(path.relative_to(install)), 'sha256': sha(path), 'bytes': path.stat().st_size}
             for path in sorted(install.rglob('*')) if path.is_file()]
    receipt = {'source_commit': commit, 'compiler': str(compiler), 'compiler_sha256': compiler_hash,
               'host_build_command': build, 'installation': str(install), 'installation_files': files,
               'component_provenance': str(ROOT / 'experiments/micro-gaps-20261012/coordinator/installation.json'),
               'entries': entries, 'qualification': '100 independent oracle probes; counted probes require counters, zero RC and zero exit-live',
               'compile_time_note': 'Build logs include admission and are not paired compiler performance evidence.'}
    save(evidence / 'build-receipt.json', receipt)
    print(evidence / 'build-receipt.json', flush=True)


if __name__ == '__main__':
    main()
