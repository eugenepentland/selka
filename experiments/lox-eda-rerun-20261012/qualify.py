#!/usr/bin/env python3
"""Qualify fresh application executables without writing historical evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    a = p.parse_args()
    manifest = json.loads(a.manifest.read_text())
    app = manifest['application']
    dest = HERE / 'qualification' / app
    dest.mkdir(parents=True, exist_ok=False)
    work = ROOT / '.tmp/lox-eda-rerun-20261012/qualification' / app
    work.mkdir(parents=True, exist_ok=False)
    common = json.loads(Path(manifest['common_receipt']).read_text())
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1', TMPDIR=str(work),
               MYLANG_COMPONENT_DIR=str(Path(common['installation']) / 'libexec/mylang/components'))
    commands = []
    def run(name, command):
        with (dest / (name + '.stdout')).open('w') as out, (dest / (name + '.stderr')).open('w') as err:
            result = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command], cwd=ROOT, env=env, stdout=out, stderr=err)
        commands.append({'name': name, 'command': command, 'returncode': result.returncode})
        (dest / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        print(app, name, result.returncode, flush=True)
        assert result.returncode == 0, name
    for binary in manifest['binaries'].values():
        assert hashlib.sha256(Path(binary['path']).read_bytes()).hexdigest() == binary['sha256']
    compiler = manifest['compiler']
    source = manifest['sources']['migrated']['root']
    unit = [compiler, 'test', source, '--experimental-zero-rc', '--release', '--verify-facts',
            '--jobs', '4', '--max-steps', '1000000000', '--max-frames', '40000',
            '--max-memory', '2G', '--timeout-ms', '120000', '--cache-dir', str(work / 'cache'), '--json']
    run('checked-tests', unit)
    if app == 'lox':
        harness = Path('/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/harness/lox_bench.py')
        (dest / 'harness.json').write_text(json.dumps({'path': str(harness), 'sha256': hashlib.sha256(harness.read_bytes()).hexdigest()}, indent=2) + '\n')
        for arm in ('original-rc', 'migrated-rc', 'zero-rc'):
            run('conformance-' + arm, ['python3', '-B', str(harness), 'conformance', '--binary', manifest['binaries'][arm]['path'], '--engine', 'both', '--stress', '--jobs', '4'])
        command = ['python3', '-B', str(harness), 'check', '--tier', 'smoke', '--jobs', '4']
        for arm in ('original-rc', 'migrated-rc', 'zero-rc'):
            command += ['--binary', arm + '=' + manifest['binaries'][arm]['path']]
        run('smoke-gc-parity', command)
    (dest / 'qualified.json').write_text(json.dumps({'manifest': str(a.manifest.resolve()), 'manifest_sha256': hashlib.sha256(a.manifest.read_bytes()).hexdigest(), 'status': 'passed', 'commands': commands}, indent=2) + '\n')


if __name__ == '__main__':
    main()
