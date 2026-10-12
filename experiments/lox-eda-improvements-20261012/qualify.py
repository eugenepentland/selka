#!/usr/bin/env python3
"""Qualify fresh application executables without writing historical evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import re
import sys
from receipts import sha, validate_build

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    a = p.parse_args()
    manifest = validate_build(a.manifest)
    app = manifest['application']
    dest = HERE / 'qualification' / app
    dest.mkdir(parents=True, exist_ok=False)
    work = ROOT / '.tmp/lox-eda-improvements-20261012/qualification' / app
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
    tests = json.loads((dest / 'checked-tests.stdout').read_text())
    assert tests['passed'] == (69 if app == 'lox' else 317), 'integrated unit-test denominator changed'
    assert all(tests[key] == 0 for key in ('failed', 'skipped', 'unsupported'))
    if app == 'lox':
        harness = Path('/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/harness/lox_bench.py')
        (dest / 'harness.json').write_text(json.dumps({'path': str(harness), 'sha256': hashlib.sha256(harness.read_bytes()).hexdigest()}, indent=2) + '\n')
        corpus_root = harness.parent.parent / 'corpus/test'
        corpus = {str(path): sha(path) for path in sorted(corpus_root.rglob('*.lox'))}
        assert len(corpus) >= 246
        (dest / 'conformance-inputs.json').write_text(json.dumps(corpus, indent=2) + '\n')
        for arm in ('original-rc', 'migrated-rc', 'zero-rc'):
            run('conformance-' + arm, ['python3', '-B', str(harness), 'conformance', '--binary', manifest['binaries'][arm]['path'], '--engine', 'both', '--stress', '--jobs', '4'])
            observed = re.findall(r'conformance engine=(vm|tree) gc=(normal|gc-stress): (\d+)/(\d+) passed',
                                  (dest / ('conformance-' + arm + '.stdout')).read_text())
            expected = {(engine, mode, str(count), str(count)) for engine, count in (('vm', 246), ('tree', 241))
                        for mode in ('normal', 'gc-stress')}
            assert len(observed) == 4 and set(observed) == expected
        command = ['python3', '-B', str(harness), 'check', '--tier', 'smoke', '--jobs', '4']
        for arm in ('original-rc', 'migrated-rc', 'zero-rc'):
            command += ['--binary', arm + '=' + manifest['binaries'][arm]['path']]
        run('smoke-gc-parity', command)
        assert corpus == {str(path): sha(path) for path in sorted(corpus_root.rglob('*.lox'))}
    else:
        run('goldens', [sys.executable, '-B', str(HERE / 'qualify_goldens.py'), str(a.manifest.resolve()),
                        str(dest / 'goldens.json'), str(work / 'golden-work')])
        run('error-paths', [sys.executable, '-B', str(HERE / 'check-error-paths.py'),
            *[arm + '=' + manifest['binaries'][arm]['path'] for arm in ('original-rc', 'migrated-rc', 'zero-rc')]])
        errors = json.loads((HERE / 'error-paths.json').read_text())
        assert errors['pass'] and len(errors['cases']) == 9
    validate_build(a.manifest)
    evidence = {str(path): sha(path) for path in sorted(dest.iterdir()) if path.is_file()}
    if app == 'eda':
        evidence[str(HERE / 'error-paths.json')] = sha(HERE / 'error-paths.json')
    (dest / 'qualified.json').write_text(json.dumps({'manifest': str(a.manifest.resolve()), 'manifest_sha256': hashlib.sha256(a.manifest.read_bytes()).hexdigest(), 'status': 'passed', 'commands': commands, 'evidence': evidence}, indent=2) + '\n')


if __name__ == '__main__':
    main()
