#!/usr/bin/env python3
"""Exact installed ordinary-sequence admission, independent of generator support."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import run_body_check_qualification as D
import run_body_numeric_admission as N

F = D.F
SCHEMA = D.SCHEMA
MODES = ('reference', 'shadow', 'component')
FIXTURES = Path(__file__).with_name('fixtures') / 'body_sequence_candidate'
COUNTS = {'fixtures': 126, 'success': 97, 'diagnostic': 29, 'runtime_traps': 10, 'profiles': 0}
WIDTHS = ('i8', 'i16', 'i32', 'int', 'u8', 'u16', 'u32', 'u64')


def require_selection(manifest, inventory):
    F.require(inventory['schema'] == SCHEMA, 'ordinary sequence schema differs')
    F.require(inventory['counts'] == COUNTS and len(manifest) == COUNTS['fixtures'],
              'incomplete ordinary sequence inventory')
    F.require(inventory['source_cases'] == list(manifest), 'sequence source order changed')
    F.require(all(Path(name).name == name and name.endswith('.my') for name in manifest),
              'unsafe sequence source name')
    F.require(all(type(s['status']) is int and s['status'] in (0, 1) for s in manifest.values()),
              'profile refusals cannot satisfy sequence admission')
    F.require(sum(s['status'] == 0 for s in manifest.values()) == COUNTS['success']
              and sum(s['status'] == 1 for s in manifest.values()) == COUNTS['diagnostic'],
              'sequence success/diagnostic selection changed')
    traps = [name for name, spec in manifest.items() if spec.get('runtime', {}).get('trap')]
    F.require(len(traps) == COUNTS['runtime_traps'] and traps == inventory['runtime_trap_cases'],
              'sequence trap selection changed')
    F.require(all(bool(s.get('diagnostics')) == (s['status'] == 1) for s in manifest.values()),
              'sequence ordered diagnostic contract missing')
    F.require(all((s.get('runtime') is not None) == (s['status'] == 0) for s in manifest.values()),
              'sequence runtime contract missing or assigned to source error')
    F.require(tuple(inventory['integer_widths']) == WIDTHS, 'sequence integer widths changed')
    for width in WIDTHS:
        for operation in ('sum', 'min', 'max', 'sorted', 'extreme_pair', 'reverse', 'overflow_sum'):
            spec = manifest.get(operation + '_' + width + '.my')
            F.require(spec is not None and spec['status'] == 0, 'sequence width control missing')
            F.require(spec['runtime']['trap'] == (operation == 'overflow_sum'),
                      'sequence integer overflow control changed')


def selection():
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())
    inventory = json.loads((FIXTURES / 'inventory.json').read_text())
    require_selection(manifest, inventory)
    F.require(set(manifest) == {p.with_suffix('.my').name for p in FIXTURES.glob('*.input')},
              'unselected or missing sequence fixture')
    for name, spec in manifest.items():
        F.require(F.digest(FIXTURES / Path(name).with_suffix('.input')) == spec['source_sha256'],
                  'sequence source changed: ' + name)
    return manifest, inventory


def expected_operations(manifest, checks_only=False):
    if checks_only:
        return len(manifest) * len(MODES)
    return (2 * len(manifest) + 2 * sum(s['status'] == 0 for s in manifest.values())) * len(MODES)


def identity(args):
    return {'compiler_sha256': F.digest(args.compiler),
            'packages': D.packages(args.component_dir, body_schema=SCHEMA)}


def warning_contract(stderr, expected, entry=None):
    rows = [json.loads(line) for line in stderr.splitlines()]
    F.require(all(row['version'] == 'diagnostic-v1' and row['kind'] == 'diagnostic'
                  and row['diagnostic']['severity'] == 'warning' for row in rows),
              'sequence success emitted a host failure or error')
    if entry is not None:
        F.require(all(row['diagnostic']['location']['path'] == str(entry) for row in rows),
                  'sequence runtime warning has foreign source provenance')
    F.require([D.diagnostic_contract(row['diagnostic']) for row in rows] == expected,
              'sequence source warning contract changed')


def native_contract(result, spec):
    if spec['status'] == 1:
        N.native_contract(result, spec)
        return
    F.require(result[0] == 0 and not result[1], 'native sequence status/stdout differs')
    warning_contract(result[2], spec.get('warnings', []))


def runtime_contract(result, spec, entry):
    runtime = spec['runtime']
    if runtime['trap']:
        N.runtime_contract(result, spec, entry)
        return
    F.require(result[0] == runtime['status'] and result[1].hex() == runtime['stdout_hex'],
              'native sequence runtime status/output differs')
    warning_contract(result[2], runtime.get('warnings', []), entry)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--component-dir', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--builder', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=D.ROOT)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--checks-only', action='store_true')
    args = parser.parse_args()
    for name in ('compiler', 'component_dir', 'zig', 'builder', 'source_root', 'report'):
        setattr(args, name, getattr(args, name).resolve())
    manifest, inventory = selection()
    before = identity(args)
    report = {'complete': False, 'selected_admission': 'pending', 'body_schema': SCHEMA,
              'scope': 'ordinary keyless sequence calls; callbacks and generators remain separate',
              'lane': 'release' if args.release else 'normal', 'checks_only': args.checks_only,
              'expected_operations': expected_operations(manifest, args.checks_only),
              'modes': list(MODES), 'counts': COUNTS, 'selection': manifest,
              **before, 'records': [], 'qualified_seed_sha256': None}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def checkpoint():
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    checkpoint()
    seed = F.execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                     D.coordinator_environment(), args.source_root, 600)
    report['seed_verification'] = {'status': seed[0], 'stdout_hex': seed[1].hex(), 'stderr_hex': seed[2].hex()}
    checkpoint()
    lines = seed[1].decode().strip().splitlines()
    F.require(seed[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(),
              'sequence qualified seed verification failed')
    report['qualified_seed_sha256'] = F.digest(Path(lines[0]))
    with tempfile.TemporaryDirectory(prefix='body-sequence-admission-') as directory:
        work = Path(directory)
        sources = work / 'sources'; sources.mkdir()
        empty = work / 'empty-path'; empty.mkdir()
        def run(name, mode, phase, command):
            environment = D.environment(mode, args.component_dir, empty)
            if phase == 'syntax':
                environment.update(MYLANG_BODY_CHECK_MODE='reference', MYLANG_PARSER_MODE=mode)
            argv = [args.compiler, *command]
            result = F.execute(argv, environment, work, 600)
            report['records'].append({'name': name, 'mode': mode, 'phase': phase,
                'command': list(map(str, argv)), 'source_sha256': manifest[name]['source_sha256'],
                'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex(),
                'stdout_sha256': hashlib.sha256(result[1]).hexdigest(),
                'stderr_sha256': hashlib.sha256(result[2]).hexdigest()})
            checkpoint()
            return result
        for name, spec in manifest.items():
            entry = sources / name
            shutil.copyfile(FIXTURES / Path(name).with_suffix('.input'), entry)
            phases = ['check'] if args.checks_only else ['syntax', 'check']
            if not args.checks_only and spec['status'] == 0:
                phases += ['typed', 'runtime']
            for phase in phases:
                if phase == 'syntax':
                    command = ['dump-syntax', entry]
                elif phase == 'check':
                    command = ['check-project', entry, '--no-cache', '--diagnostics=json']
                elif phase == 'typed':
                    command = ['dump-typed', entry]
                else:
                    command = ['run-project', entry, '--no-cache', '--print-result', '--diagnostics=json',
                               '--cache-dir', work / 'guest-cache', f'--zig={args.zig}']
                    if args.release:
                        command += ['--release', '--verify-facts']
                native = run(name, 'reference', phase, command)
                if phase == 'check':
                    native_contract(native, spec)
                elif phase == 'runtime':
                    runtime_contract(native, spec, entry)
                else:
                    F.require(native[0] == 0 and native[1] and not native[2],
                              'native sequence syntax/typed output failed')
                for mode in MODES[1:]:
                    F.require(run(name, mode, phase, command) == native,
                              'selected sequence tuple differs: ' + name + ':' + phase + ':' + mode)
                print('exact', name, phase, flush=True)
    F.require(identity(args) == before, 'sequence deployment changed')
    F.require(selection() == (manifest, inventory), 'sequence selection changed')
    F.require(len(report['records']) == expected_operations(manifest, args.checks_only),
              'incomplete sequence operation accounting')
    report.update(complete=True, selected_admission='passed', operations=len(report['records']), failed=0, skipped=0)
    checkpoint()
    print('ordinary sequence passed:', report['operations'], 'operations; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
