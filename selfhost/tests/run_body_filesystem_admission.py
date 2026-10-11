#!/usr/bin/env python3
"""Exact primitive filesystem admission with isolated normal/release runtime trials."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import run_body_check_qualification as D
import run_body_filesystem_hostile as H

F = D.F
SCHEMA = D.SCHEMA
FIXTURES = Path(__file__).with_name('fixtures') / 'body_filesystem_candidate'
COUNTS = {'fixtures': 59, 'success': 47, 'diagnostic': 12, 'runtime': 9}
MODES = ('reference', 'shadow', 'component')


def require_selection(manifest, inventory):
    F.require(inventory['counts'] == COUNTS and len(manifest) == COUNTS['fixtures'],
              'incomplete filesystem inventory')
    F.require(list(manifest) == inventory['source_cases'], 'filesystem source order changed')
    F.require(set(manifest) == {p.with_suffix('.my').name for p in FIXTURES.glob('*.input')},
              'missing/unselected filesystem fixture')
    F.require(all(Path(name).name == name and name.endswith('.my') for name in manifest),
              'unsafe filesystem fixture name')
    F.require(all(type(s['status']) is int and s['status'] in (0, 1) for s in manifest.values()),
              'profile refusal cannot satisfy filesystem admission')
    F.require(sum(s['status'] == 0 for s in manifest.values()) == COUNTS['success'] and
              sum(s['status'] == 1 for s in manifest.values()) == COUNTS['diagnostic'],
              'filesystem success/diagnostic selection changed')
    F.require(all(type(s['runtime']) is bool and (not s['runtime'] or s['status'] == 0)
                  for s in manifest.values()) and
              sum(s['runtime'] for s in manifest.values()) == COUNTS['runtime'],
              'filesystem runtime selection changed')
    F.require(all(bool(s['diagnostics']) == (s['status'] == 1) for s in manifest.values()),
              'filesystem ordered diagnostics missing')
    F.require(inventory['data_files'] == {'text.txt': '736576656e21210a'},
              'filesystem runtime data changed')


def selection():
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())
    inventory = json.loads((FIXTURES / 'inventory.json').read_text())
    require_selection(manifest, inventory)
    for name, spec in manifest.items():
        F.require(F.digest(FIXTURES / Path(name).with_suffix('.input')) == spec['source_sha256'],
                  'filesystem source changed: ' + name)
    return manifest, inventory


def expected_operations(manifest):
    # Every case checks; accepted cases dump typed; runtime cases execute in both
    # normal and release/facts/leak modes, each in a fresh filesystem directory.
    return len(MODES) * (len(manifest) + sum(s['status'] == 0 for s in manifest.values()) +
                         2 * sum(s['runtime'] for s in manifest.values()))


def native_contract(result, spec):
    F.require(result[0] == spec['status'] and result[1] == b'',
              'native filesystem status/stdout differs')
    records = [json.loads(line) for line in result[2].splitlines()]
    F.require(all(r['version'] == 'diagnostic-v1' and r['kind'] == 'diagnostic' and
                  r['diagnostic']['severity'] == 'error' for r in records),
              'native filesystem output is not source diagnostics')
    F.require([D.diagnostic_contract(r['diagnostic']) for r in records] == spec['diagnostics'],
              'native filesystem diagnostic precedence/repair changed')


def require_match(native, selected):
    F.require(selected == native, 'selected filesystem tuple differs from native')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--builder', type=Path, required=True)
    parser.add_argument('--component-dir', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=D.ROOT)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    for name, value in vars(args).items():
        setattr(args, name, value.resolve())
    manifest, inventory = selection()
    before = {'compiler_sha256': F.digest(args.compiler), 'packages': D.packages(args.component_dir)}
    sources = {str(p.relative_to(args.source_root)): F.digest(p) for p in
               sorted((args.source_root / 'selfhost/components/body_check').glob('*.my'))}
    report = {'complete': False, 'selected_admission': 'pending', 'body_schema': SCHEMA,
              'scope': 'primitive filesystem checking, typed graphs and generated execution; no bootstrap/performance claim',
              **before, **COUNTS, 'source_sha256': sources,
              'fixture_sha256': {name: s['source_sha256'] for name, s in manifest.items()},
              'data_files': inventory['data_files'], 'expected_operations': expected_operations(manifest),
              'modes': list(MODES), 'runtime_modes': ['normal', 'release/facts/leaks'], 'records': []}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def checkpoint():
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    checkpoint()
    seed = F.execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                     D.coordinator_environment(), args.source_root, 600)
    report['seed_verification'] = {'status': seed[0], 'stdout_hex': seed[1].hex(), 'stderr_hex': seed[2].hex()}
    checkpoint()
    lines = seed[1].decode().strip().splitlines()
    F.require(seed[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(), 'filesystem seed verification failed')
    report['qualified_seed_sha256'] = F.digest(Path(lines[0]))
    F.require(report['qualified_seed_sha256'] ==
              'c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b',
              'qualified filesystem seed changed')
    with tempfile.TemporaryDirectory(prefix='body-filesystem-admission-') as temporary:
        work = Path(temporary)
        empty = work / 'empty-path'; empty.mkdir()
        def run(name, mode, phase, command, cwd):
            argv = [args.compiler, *command]
            result = F.execute(argv, D.environment(mode, args.component_dir, empty), cwd, 600)
            report['records'].append({'name': name, 'mode': mode, 'phase': phase,
                'source_sha256': manifest[name]['source_sha256'], 'command': list(map(str, argv)),
                'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex(),
                'stdout_sha256': hashlib.sha256(result[1]).hexdigest(),
                'stderr_sha256': hashlib.sha256(result[2]).hexdigest()})
            checkpoint()
            return result
        for name, spec in manifest.items():
            source = work / name
            source.write_bytes((FIXTURES / Path(name).with_suffix('.input')).read_bytes())
            command = ['check-project', source, '--no-cache', '--diagnostics=json']
            native = run(name, 'reference', 'check', command, work)
            native_contract(native, spec)
            for mode in MODES[1:]:
                require_match(native, run(name, mode, 'check', command, work))
            if spec['status'] == 0:
                command = ['dump-typed', source]
                native = run(name, 'reference', 'typed', command, work)
                F.require(native[0] == 0 and native[1] and native[2] == b'', 'empty/failed native filesystem typed output')
                for mode in MODES[1:]:
                    require_match(native, run(name, mode, 'typed', command, work))
            if spec['runtime']:
                for release in (False, True):
                    phase = 'runtime-release' if release else 'runtime-normal'
                    for mode in MODES:
                        trial = work / (Path(name).stem + '-' + mode + '-' + phase); trial.mkdir()
                        entry = trial / name; entry.write_bytes(source.read_bytes())
                        for filename, data in inventory['data_files'].items():
                            (trial / filename).write_bytes(bytes.fromhex(data))
                        command = ['run-project', entry, '--no-cache', '--print-result',
                                   '--cache-dir', trial / 'cache', f'--zig={args.zig}',
                                   *(['--release', '--verify-facts'] if release else [])]
                        require_match((7, b'7\n', b''), run(name, mode, phase, command, trial))
        report['hostile_expected'] = H.EXPECTED
        report['hostile_complete'] = False
        def hostile_checkpoint(records, captures):
            report['hostile_records'] = records
            report['hostile_captures'] = captures
            checkpoint()
        H.run(args, args.report.parent / (args.report.stem + '-hostile'), empty, hostile_checkpoint)
        report['hostile_complete'] = True
        checkpoint()
    F.require(before == {'compiler_sha256': F.digest(args.compiler), 'packages': D.packages(args.component_dir)},
              'filesystem compiler/package deployment changed')
    F.require(sources == {name: F.digest(args.source_root / name) for name in sources},
              'filesystem producer source changed during verification')
    selection()
    F.require(len(report['records']) == expected_operations(manifest) == 372, 'incomplete filesystem accounting')
    report.update(complete=True, selected_admission='passed', operations=372, failed=0, skipped=0)
    checkpoint()
    print('filesystem passed: 59 fixtures, 372 operations; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
