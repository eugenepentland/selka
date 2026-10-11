#!/usr/bin/env python3
"""Additional dictionary/set/gather coverage; profile refusals never pass."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import run_body_dictionary_admission as A

D = A.D
F = D.F
SCHEMA = 10
FIXTURES = Path(__file__).with_name('fixtures') / 'body_collection_extensions'
CASES = (
    'dict_augmentation.my', 'dict_expression_receiver.my',
    'dictionary_augmentation_nested.my', 'dictionary_generator_pairs.my',
    'dictionary_items_membership.my', 'nested_dictionary_gather.my',
    'option_dictionary_mutation.my', 'option_set_mutation.my',
    'set_expression_receiver.my', 'set_generator.my',
)


def selection():
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())
    F.require(tuple(manifest) == CASES, 'incomplete collection extension inventory')
    F.require(set(manifest) == {p.with_suffix('.my').name for p in FIXTURES.glob('*.input')},
              'unselected collection extension source')
    for name, spec in manifest.items():
        F.require(type(spec['status']) is int and spec['status'] == 0,
                  'collection extensions require successful native programs')
        F.require(F.digest(FIXTURES / Path(name).with_suffix('.input')) == spec['source_sha256'],
                  'changed collection extension source: ' + name)
    return manifest


def runtime_contract(result):
    F.require(result == (7, b'7\n', b''), 'collection extension release/facts/leaks behavior differs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'component-dir', 'zig', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--builder', type=Path)
    parser.add_argument('--source-root', type=Path, default=D.ROOT)
    parser.add_argument('--native-controls', action='store_true')
    args = parser.parse_args()
    for name in ('compiler', 'component_dir', 'zig', 'report', 'builder', 'source_root'):
        value = getattr(args, name)
        if value is not None:
            setattr(args, name, value.resolve())
    manifest = selection()
    modes = ('reference',) if args.native_controls else ('reference', 'component', 'shadow')

    def identity():
        return {'host_sha256': F.digest(args.compiler),
                'packages': D.packages(args.component_dir, body_schema=SCHEMA)}

    before = identity()
    report = {'complete': False, 'selected_admission': 'pending',
              'scope': 'Ten additional collection source cases; no full-language/bootstrap claim',
              'schema': SCHEMA, 'native_controls': args.native_controls, **before,
              'modes': list(modes), 'expected_operations': len(CASES) * 3 * len(modes),
              'runtime_flags': ['--release', '--verify-facts', 'MYL_CORE_LEAKCHECK=1'],
              'qualified_seed_sha256': None, 'records': []}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')

    save()
    if not args.native_controls:
        F.require(args.builder is not None, 'selected collection extensions require seed verification')
        result = F.execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                           D.coordinator_environment(), args.source_root, 600)
        report['seed_verification'] = {'status': result[0], 'stdout_hex': result[1].hex(),
                                       'stderr_hex': result[2].hex()}
        save()
        lines = result[1].decode().strip().splitlines()
        F.require(result[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(),
                  'collection extensions qualified seed receipt failed')
        report['qualified_seed_sha256'] = F.digest(Path(lines[0]))
    with tempfile.TemporaryDirectory(prefix='body-collection-extensions-') as directory:
        work = Path(directory)
        empty = work / 'empty-path'
        empty.mkdir()

        def run(name, mode, phase, command):
            argv = [args.compiler, *command]
            result = F.execute(argv, D.environment(mode, args.component_dir, empty), work, 600)
            report['records'].append({'name': name, 'mode': mode, 'phase': phase,
                'command': list(map(str, argv)), 'source_sha256': manifest[name]['source_sha256'],
                'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()})
            save()
            return result

        for name, spec in manifest.items():
            entry = work / name
            shutil.copyfile(FIXTURES / Path(name).with_suffix('.input'), entry)
            command = A.check_command(entry)
            reference = run(name, 'reference', 'check', command)
            A.native_contract(reference, spec)
            for mode in modes[1:]:
                A.require_match(reference, run(name, mode, 'check', command))
            command = ['dump-typed', entry]
            reference = run(name, 'reference', 'typed', command)
            F.require(reference[0] == 0 and reference[1] and not reference[2],
                      'missing native collection extension typed output')
            for mode in modes[1:]:
                A.require_match(reference, run(name, mode, 'typed', command))
            command = ['run-project', entry, '--no-cache', '--release', '--verify-facts',
                       '--print-result', '--cache-dir', work / 'guest-cache', '--zig=' + str(args.zig)]
            for mode in modes:
                runtime_contract(run(name, mode, 'runtime', command))
    F.require(identity() == before, 'collection extension deployment changed')
    F.require(len(report['records']) == report['expected_operations'], 'incomplete extension operations')
    report.update(complete=True, selected_admission='pending' if args.native_controls else 'passed',
                  failed=0, skipped=0, operations=len(report['records']))
    save()
    print(f'collection extensions: {report["operations"]} operations passed; selected admission '
          + report['selected_admission'])


if __name__ == '__main__':
    main()
