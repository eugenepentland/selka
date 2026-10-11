#!/usr/bin/env python3
"""Frozen native B10 controls; no selected schema or admission claim."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import run_body_check_qualification as D

F = D.F
ROOT = Path(__file__).with_name('fixtures') / 'body_array_candidate'


def selection():
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    F.require(len(manifest) == 12 and sum(s['status'] == 0 for s in manifest.values()) == 6,
              'incomplete B10 native inventory')
    F.require(set(manifest) == {p.with_suffix('.my').name for p in ROOT.glob('*.input')},
              'unselected or missing B10 source')
    for name, spec in manifest.items():
        F.require(F.digest(ROOT / Path(name).with_suffix('.input')) == spec['source_sha256'],
                  'changed B10 source')
        F.require(spec['status'] in (0, 1) and bool(spec['diagnostics']) == (spec['status'] == 1),
                  'profile or missing native diagnostic')
    return manifest


def check(result, spec):
    F.require(result[0] == spec['status'] and not result[1], 'native status/stdout changed')
    diagnostics = []
    for line in result[2].splitlines():
        row = json.loads(line)
        F.require(row['version'] == 'diagnostic-v1' and row['kind'] == 'diagnostic'
                  and row['diagnostic']['severity'] == 'error', 'not a source error')
        diagnostics.append(D.diagnostic_contract(row['diagnostic']))
    F.require(diagnostics == spec['diagnostics'], 'native diagnostic/repair changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('compiler', 'component-dir', 'zig', 'report'):
        parser.add_argument('--' + flag, type=Path, required=True)
    parser.add_argument('--native-body-schema', type=int, required=True)
    args = parser.parse_args()
    for field in ('compiler', 'component_dir', 'zig', 'report'):
        setattr(args, field, getattr(args, field).resolve())
    manifest = selection()
    identity = {'host': F.digest(args.compiler),
                'packages': D.packages(args.component_dir, body_schema=args.native_body_schema)}
    report = {'selected_admission': 'pending', 'native_only': True, 'identity': identity,
              'expected_operations': 24, 'records': [], 'complete': False}
    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    save()
    with tempfile.TemporaryDirectory(prefix='body-array-controls-') as directory:
        work = Path(directory); empty = work / 'empty'; empty.mkdir()
        env = D.environment('reference', args.component_dir, empty)
        def run(name, phase, command):
            result = F.execute([args.compiler, *command], env, work, 600)
            report['records'].append({'name': name, 'phase': phase, 'status': result[0],
                'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex(),
                'source_sha256': manifest[name]['source_sha256']})
            save()  # Failed verdicts remain evidence.
            return result
        for name, spec in manifest.items():
            entry = work / name
            shutil.copyfile(ROOT / Path(name).with_suffix('.input'), entry)
            check(run(name, 'check', ['check-project', entry, '--no-cache', '--diagnostics=json']), spec)
            if spec['status'] == 0:
                typed = run(name, 'typed', ['dump-typed', entry])
                F.require(typed[0] == 0 and typed[1] and not typed[2], 'missing native typed output')
                result = run(name, 'runtime', ['run', entry, '--release', '--verify-facts',
                    '--no-cache', '--print-result', '--zig=' + str(args.zig)])
                F.require(result == (7, b'7\n', b''), 'native release/facts/leaks result differs')
    F.require(identity == {'host': F.digest(args.compiler),
        'packages': D.packages(args.component_dir, body_schema=args.native_body_schema)}, 'deployment drift')
    F.require(len(report['records']) == 24, 'incomplete operations')
    report['complete'] = True; save()
    print('B10 native controls: 24 operations passed; selected admission pending')


if __name__ == '__main__':
    main()
