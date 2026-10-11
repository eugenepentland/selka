#!/usr/bin/env python3
"""Qualify the Selka entry adapter against complete native typed programs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'selfhost'))
from test_pilots import require_guest

SEED_SHA = 'c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('seed', 'zig', 'work', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for key in vars(args):
        setattr(args, key, getattr(args, key).resolve())
    if digest(args.seed) != SEED_SHA:
        raise RuntimeError('qualified seed identity differs')
    args.work.mkdir(parents=True, exist_ok=False)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    component = ROOT / 'selfhost/components/body_check'
    sources = sorted((ROOT / 'src').rglob('*.zig')) + sorted(component.glob('*.my'))
    sources += [component / 'entry_oracle.zig', ROOT / 'selfhost/test_pilots.py', Path(__file__).resolve()]
    before = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    report = dict(complete=False, source_sha256=before, seed_sha256=SEED_SHA, zig_sha256=digest(args.zig),
                  scope='Entry adapter algorithm parity; production semantic selection remains pending',
                  records=[], normal_cases=0, release_cases=0, negative_controls=0, pure_tests_per_mode=13)

    def save():
        args.report.write_text(json.dumps(report, indent=2) + '\n')

    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('MYLANG_', 'PILOT_', 'ENTRY_')) or key == 'MYLANG_COMPONENT_CACHE'}
    env.update(MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')

    def run(name, command, extra=None, negative=False):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, env={**env, **(extra or {})}, capture_output=True)
        out = args.work / (name + '.stdout')
        err = args.work / (name + '.stderr')
        out.write_bytes(result.stdout)
        err.write_bytes(result.stderr)
        report['records'].append(dict(name=name, command=list(map(str, command)), status=result.returncode,
            stdout_sha256=digest(out), stderr_sha256=digest(err), stdout=str(out), stderr=str(err),
            environment=extra or {}))
        save()
        if negative:
            if result.returncode == 0 or b'EntryParity' not in result.stderr:
                raise RuntimeError(name + ' did not reject the changed typed function')
        elif result.returncode:
            raise RuntimeError(name + ' failed: ' + result.stderr.decode(errors='replace')[-5000:])
        return result.stdout

    save()
    staged = args.work / 'native'
    staged.mkdir()
    shutil.copytree(ROOT / 'src', staged / 'src')
    shutil.copyfile(component / 'entry_oracle.zig', staged / 'entry_oracle.zig')
    oracle = staged / 'oracle'
    run('build-oracle', [args.zig, 'build-exe', staged / 'entry_oracle.zig', '-lc', '-OReleaseSafe',
                        '--cache-dir', staged / 'zig-cache', '-femit-bin=' + str(oracle)])
    report['oracle_sha256'] = digest(oracle)
    for case in range(30):
        case_env = {'ENTRY_CASE': str(case)}
        request = run('request-' + str(case), [oracle], case_env)
        if not request.startswith(b'SLKBKI01'):
            raise RuntimeError('wrong request magic')
        (args.work / ('request-' + str(case) + '.bin')).write_bytes(request)
    for release in (False, True):
        mode = 'release' if release else 'normal'
        flags = ['--release', '--verify-facts'] if release else []
        for module, count in [('entry_types_tests', 6), ('entry_adapter_tests', 7)]:
            output = run(mode + '-' + module, [args.seed, 'test', component / (module + '.my'),
                         '--force', '--no-cache', *flags])
            require_guest(output.decode(), count)
        executable = args.work / ('entry-' + mode)
        run('build-' + mode, [args.seed, 'build', component / 'entry_probe.my', '-o', executable,
                             '--no-cache', *flags])
        report[mode + '_sha256'] = digest(executable)
        for case in range(30):
            name = mode + '-' + str(case)
            request = args.work / ('request-' + str(case) + '.bin')
            reply = run(name, [executable, request])
            reply_path = args.work / (name + '.bin')
            reply_path.write_bytes(reply)
            if not reply.startswith(b'SLKBKR01'):
                raise RuntimeError(name + ' wrong reply magic')
            run(name + '-compare', [oracle], {'ENTRY_CASE': str(case), 'ENTRY_ADAPT': '1', 'ENTRY_REPLY': str(reply_path)})
            report[mode + '_cases'] += 1
            save()
        valid = (args.work / (mode + '-3.bin')).read_bytes()
        if b'<entry>' not in valid:
            raise RuntimeError('missing synthesized function for negative control')
        changed = args.work / (mode + '-changed.bin')
        changed.write_bytes(valid.replace(b'<entry>', b'<other>'))
        run(mode + '-negative', [oracle], {'ENTRY_CASE': '3', 'ENTRY_ADAPT': '1', 'ENTRY_REPLY': str(changed)}, negative=True)
        report['negative_controls'] += 1
        save()
    if report['normal_cases'] != 30 or report['release_cases'] != 30 or report['negative_controls'] != 2:
        raise RuntimeError('incomplete entry adapter selection')
    if before != {str(path.relative_to(ROOT)): digest(path) for path in sources} or digest(args.seed) != SEED_SHA:
        raise RuntimeError('entry qualification source or seed changed')
    report.update(complete=True, failed=0, skipped=0)
    save()
    print('entry adapter: 30 complete native comparisons and 13 pure tests per guest mode; 2 negative controls; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
