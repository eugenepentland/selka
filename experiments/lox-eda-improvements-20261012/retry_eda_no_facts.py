#!/usr/bin/env python3
"""Preserve a component I/O failure and retry the unchanged mode on private disk storage."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from receipts import build_path, qualified, validate_build

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = build_path('eda')
    build = validate_build(manifest)
    qualified('eda', manifest)
    dest = HERE / 'matrix/eda'
    journal = dest / 'results.json'
    rows = json.loads(journal.read_text())
    label = 'no-facts-units'
    previous = rows[label]
    assert previous['returncode'] == 2
    assert 'write request failed: DiskQuota' in (dest / (label + '.stderr')).read_text()
    for mode in ('verified-release', 'release', 'debug', 'optimized-debug'):
        result = rows[mode + '-units']['result']
        assert result['passed'] == 317
        assert all(result[key] == 0 for key in ('failed', 'skipped', 'unsupported', 'cached'))
    preserved = dest / 'no-facts-attempt1'
    preserved.mkdir()
    for name in ('results.json', label + '.stdout', label + '.stderr'):
        shutil.copyfile(dest / name, preserved / name)
    work = ROOT / '.tmp/lox-eda-improvements-20261012/matrix-eda-no-facts-retry'
    work.mkdir(parents=True, exist_ok=False)
    command = list(previous['command'])
    assert command[0] == build['compiler'] and '--no-facts' in command
    assert '--experimental-zero-rc' in command and '--release' in command
    command[command.index('--cache-dir') + 1] = str(work / 'tests')
    common = json.loads(Path(build['common_receipt']).read_text())
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1', TMPDIR=str(work), MYLANG_JOBS='4',
               MYLANG_COMPONENT_DIR=str(Path(common['installation']) / 'libexec/mylang/components'))
    note = {'reason': 'Cache-plan request write failed with DiskQuota before guest test results. '
                     'Retry changes only temporary directory and fresh cache location; same compiler, source, flags and leak check.',
            'manifest_sha256': sha(manifest), 'previous': previous, 'retry_command': command,
            'retry_tmpdir': str(work),
            'preserved': {str(path): sha(path) for path in sorted(preserved.iterdir())}}
    (dest / 'no-facts-retry.json').write_text(json.dumps(note, indent=2) + '\n')
    with (dest / (label + '.stdout')).open('w') as out, (dest / (label + '.stderr')).open('w') as err:
        result = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command],
                                cwd=ROOT, env=env, stdout=out, stderr=err)
    row = {'command': command, 'returncode': result.returncode,
           'retry_evidence': str(dest / 'no-facts-retry.json')}
    if result.returncode == 0:
        row['result'] = json.loads((dest / (label + '.stdout')).read_text())
    rows[label] = row
    journal.write_text(json.dumps(rows, indent=2) + '\n')
    assert result.returncode == 0, 'no-facts retry failed; evidence preserved'
    tests = row['result']
    assert tests['passed'] == 317
    assert all(tests[key] == 0 for key in ('failed', 'skipped', 'unsupported', 'cached'))
    validate_build(manifest)
    qualified('eda', manifest)
    print('PASS eda all five checked ownership modes; no-facts317 passed on fresh private disk cache', flush=True)


if __name__ == '__main__':
    main()
