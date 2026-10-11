#!/usr/bin/env python3
"""Strict B8 source admission; native controls never count as selected support."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import run_body_check_qualification as D

F = D.F
SCHEMA = 8
FIXTURES = Path(__file__).with_name('fixtures') / 'body_dictionary_candidate'
COUNTS = {'fixtures': 34, 'success': 24, 'diagnostic': 10, 'profiles': 0}
MODES = ('reference', 'shadow', 'component')


def selection():
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())
    inventory = json.loads((FIXTURES / 'inventory.json').read_text())
    require_selection(manifest, inventory)
    for name, spec in manifest.items():
        F.require(F.digest(FIXTURES / Path(name).with_suffix('.input')) == spec['source_sha256'],
                  'fixture source changed: ' + name)
    F.require(set(inventory['donors']) == {p.name for p in FIXTURES.glob('*.my')},
              'missing/unselected dictionary donor')
    for name, digest in inventory['donors'].items():
        F.require(F.digest(FIXTURES / name) == digest, 'dictionary donor changed: ' + name)
    return manifest, inventory


def require_selection(manifest, inventory):
    F.require(inventory['counts'] == COUNTS and len(manifest) == COUNTS['fixtures'],
              'incomplete B8 selection')
    F.require(list(manifest) == inventory['source_cases'], 'B8 source order/inventory differs')
    F.require(set(manifest) == {p.with_suffix('.my').name for p in FIXTURES.glob('*.input')},
              'missing/unselected B8 fixture')
    F.require(all(Path(name).name == name and name.endswith('.my') for name in manifest),
              'unsafe B8 source name')
    F.require(all(type(s['status']) is int and s['status'] in (0, 1) for s in manifest.values()),
              'B8 profile refusal cannot satisfy admission')
    F.require(sum(s['status'] == 0 for s in manifest.values()) == COUNTS['success'],
              'B8 success count changed')
    F.require(sum(s['status'] == 1 for s in manifest.values()) == COUNTS['diagnostic'],
              'B8 diagnostic count changed')
    F.require(all(bool(s.get('diagnostics')) == (s['status'] == 1) for s in manifest.values()),
              'missing ordered native diagnostics')


def native_contract(result, spec):
    F.require(result[0] == spec['status'] and result[1] == b'', 'native B8 status/stdout differs')
    if spec['status'] == 0:
        F.require(result[2] == b'', 'unexpected native B8 warnings')
        return
    try:
        records = [json.loads(line) for line in result[2].splitlines()]
        F.require(records and all(r['version'] == 'diagnostic-v1' and r['kind'] == 'diagnostic'
                  and r['diagnostic']['severity'] == 'error' for r in records),
                  'native B8 refusal is not source diagnostics')
        diagnostics = [D.diagnostic_contract(r['diagnostic']) for r in records]
    except (ValueError, KeyError, TypeError) as error:
        raise RuntimeError('malformed native B8 diagnostic') from error
    F.require(diagnostics == spec['diagnostics'], 'native B8 diagnostic precedence/repair changed')


def require_match(native, selected):
    F.require(selected == native, 'selected B8 tuple differs from native reference')


def normalize(args):
    for name in ('compiler', 'zig', 'builder', 'source_root', 'component_dir', 'report'):
        value = getattr(args, name)
        if value is not None:
            setattr(args, name, value.resolve())
    return args


def identity(args):
    return {'compiler_sha256': F.digest(args.compiler),
            'packages': D.packages(args.component_dir, body_schema=args.native_body_schema if args.native_controls else SCHEMA)}


def require_identity(args, expected):
    F.require(identity(args) == expected, 'B8 compiler/package deployment changed')


def expected_operations(manifest, modes):
    # Each fixture checks; each successful fixture additionally dumps typed and
    # runs a generated release program with facts and leak checks enabled.
    return (len(manifest) + 2 * sum(s['status'] == 0 for s in manifest.values())) * len(modes)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--zig', type=Path, required=True)
    ap.add_argument('--component-dir', type=Path, required=True)
    ap.add_argument('--builder', type=Path)
    ap.add_argument('--source-root', type=Path, default=D.ROOT)
    ap.add_argument('--report', type=Path, required=True)
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--native-controls', action='store_true')
    ap.add_argument('--native-body-schema', type=int, choices=range(1, SCHEMA + 1))
    args = normalize(ap.parse_args())
    F.require((args.native_body_schema is not None) == args.native_controls,
              'native controls require an explicit historical body schema; selected admission requires schema8')
    manifest, inventory = selection()
    modes = ('reference',) if args.native_controls else MODES
    before = identity(args)
    report = {'complete': False, 'selected_admission': 'pending', 'body_schema': SCHEMA,
              'scope': 'B8 dictionary/set/Option source fixtures; no compiler/bootstrap claim',
              'release_facts_leaks': args.release, 'native_controls': args.native_controls, 'native_body_schema': args.native_body_schema, 'modes': list(modes),
              'expected_operations': expected_operations(manifest, modes),
              **before, **COUNTS, 'donors': inventory['donors'], 'records': [],
              'runtime_flags': ['--release', '--verify-facts', 'MYL_CORE_LEAKCHECK=1'],
              'typed_oracle': 'full canonical batch/catalog shadow comparison; dump-typed supplements',
              'qualified_seed_sha256': None}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def checkpoint():
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    checkpoint()
    if not args.native_controls:
        F.require(args.builder is not None, 'selected B8 admission requires qualified-seed verification')
        result = F.execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                           D.coordinator_environment(), args.source_root, 600)
        report['seed_verification'] = {'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()}
        checkpoint()
        lines = result[1].decode().strip().splitlines()
        F.require(result[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(),
                  'B8 qualified seed receipt verification failed')
        report['qualified_seed_sha256'] = F.digest(Path(lines[0]))
    with tempfile.TemporaryDirectory(prefix='body-dictionary-admission-') as temporary:
        work = Path(temporary)
        source = work / 'sources'; source.mkdir()
        empty = work / 'empty-path'; empty.mkdir()
        for name in inventory['donors']:
            shutil.copyfile(FIXTURES / name, source / name)
        def run(name, mode, phase, command):
            argv = [args.compiler, *command]
            result = F.execute(argv, D.environment(mode, args.component_dir, empty), work, 600)
            report['records'].append({'name': name, 'mode': mode, 'phase': phase,
                'command': list(map(str, argv)), 'source_sha256': manifest[name]['source_sha256'],
                'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex(),
                'stdout_sha256': hashlib.sha256(result[1]).hexdigest(),
                'stderr_sha256': hashlib.sha256(result[2]).hexdigest()})
            checkpoint()  # Retain the failed verdict before any assertion.
            return result
        for name, spec in manifest.items():
            entry = source / name
            shutil.copyfile(FIXTURES / Path(name).with_suffix('.input'), entry)
            command = ['check-project', entry, '--no-cache', '--diagnostics=json']
            if args.release:
                command += ['--release', '--verify-facts']
            native = run(name, 'reference', 'check', command)
            native_contract(native, spec)
            for mode in modes[1:]:
                require_match(native, run(name, mode, 'check', command))
            if spec['status'] != 0:
                continue
            # Developer command's third argument is a function filter, not a cache flag.
            # Each invocation constructs a fresh frontend.Session in core/main.zig.
            command = ['dump-typed', entry]
            native = run(name, 'reference', 'typed', command)
            F.require(native[0] == 0 and native[1] and native[2] == b'', 'empty/failed native typed output')
            for mode in modes[1:]:
                require_match(native, run(name, mode, 'typed', command))
            command = ['run-project', entry, '--no-cache', '--release', '--verify-facts', '--print-result',
                       '--cache-dir', work / 'guest-cache', f'--zig={args.zig}']
            for mode in modes:
                result = run(name, mode, 'runtime', command)
                F.require(result == (7, b'7\n', b''), 'B8 generated release/fact/leak behavior differs')
    require_identity(args, before)
    F.require(len(report['records']) == expected_operations(manifest, modes), 'incomplete B8 operation accounting')
    report.update(complete=True, selected_admission='pending' if args.native_controls else 'passed',
                  operations=len(report['records']), failed=0, skipped=0)
    checkpoint()
    print(f'B8 {report["selected_admission"]}: 34 fixtures, {report["operations"]} operations; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
