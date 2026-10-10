#!/usr/bin/env python3
"""Paired edited-build comparison on identical reachable EDA replicas."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import statistics
import re
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).parents[1] / 'demand-artifacts-20261009'))
import binary_audit


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


object_audit = module('object_audit', Path(__file__).parents[1] / 'demand-builds-20261009/object_audit.py')
benchmark = module('benchmark', Path(__file__).parents[1] / 'incremental-stages-20261009/benchmark.py')
capacity = module('capacity', Path(__file__).parents[1] / 'checkpoint-reuse-20261009/single_build_cache.py')


def copy_setup_objects(previous, destination, setup):
    """Copy only setup's new objects; historical edited objects would bias timings."""
    files = {}
    for recorded in setup['new_objects']:
        source = previous / 'units-v1' / Path(recorded).name
        assert source.resolve() == Path(recorded).resolve()
        assert re.fullmatch(r'[0-9a-f]{64}\.o', source.name)
        checksum = Path(str(source) + '.sum')
        lines = checksum.read_text().splitlines()
        assert len(lines) == 3 and lines[0] == 'core-unit-sum-v1'
        assert int(lines[1]) == source.stat().st_size and re.fullmatch(r'[0-9a-f]{64}', lines[2])
        for original in (source, checksum):
            target = destination / 'units-v1' / original.name
            shutil.copy2(original, target)
            files[str(target.relative_to(destination))] = benchmark.sha(target)
    return {'source': str(previous), 'unit_object_count': len(setup['new_objects']),
            'copied_files_sha256': files,
            'verification': 'Only objects first published during validated setup copied; all historical edited objects excluded. Native cache validates BLAKE3 checksums on reuse.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--native-seed', type=Path, required=True)
    parser.add_argument('--candidate-native-extra', type=Path, help='Completed paired comparison whose validated candidate objects can seed setup')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--copies', type=int, nargs='+', default=[12, 32])
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--baseline-cache-compression', choices=['zlib', 'none'])
    parser.add_argument('--candidate-cache-compression', choices=['zlib', 'none'])
    parser.add_argument('--capture-setup-cache', action='store_true', help='Record disk allocation after each variant setup, before edits')
    parser.add_argument('--resume', action='store_true', help='Continue fresh edits in the completed output caches, writing warm-results.json')
    parser.add_argument('--resume-setup', action='store_true', help='Continue an interrupted comparison with validated setup records only')
    args = parser.parse_args()
    root = args.output.resolve()
    assert not (args.resume and args.resume_setup)
    saved_setup = json.loads((root / 'results.json').read_text()) if args.resume_setup else None
    prior = json.loads((root / 'results.json').read_text()) if args.resume else None
    if saved_setup:
        assert all(r['phase'] == 'setup' and r.get('execution_check') for r in saved_setup['records'])
        archive = root / 'setup-audit-failure.json'
        assert not archive.exists()
        archive.write_text((root / 'results.json').read_text())
    elif prior:
        assert 'completed_utc' in prior, 'Initial comparison must finish first'
        assert not (root / 'warm-results.json').exists(), 'Warm result already exists'
    else:
        root.mkdir(parents=True, exist_ok=False)
        (root / 'tmp').mkdir()
    compilers = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    compression = {'baseline': args.baseline_cache_compression, 'candidate': args.candidate_cache_compression}
    env = {k: v for k, v in os.environ.items() if not k.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    env.update(MYLANG_JOBS='4', TMPDIR=str(root / 'tmp'))
    seed_report = json.loads((args.native_seed / 'results.json').read_text())
    extra_report = json.loads((args.candidate_native_extra / 'results.json').read_text()) if args.candidate_native_extra else None
    if extra_report:
        assert 'completed_utc' in extra_report, 'Additional native seed must be complete'
        assert not args.capture_setup_cache, 'A historical native seed cannot measure one-build cache capacity'
    seed_files = [x['path'] for x in json.loads(benchmark.DEPENDENCIES.read_text())['inputs']
                  if not x['path'].startswith('@')]
    golden_manifest = benchmark.GOLDENS / 'manifest.json'
    golden = next(c for c in json.loads(golden_manifest.read_text())['cases'] if c['id'] == 'blinky-breakout')
    expected = {name: value['sha256'] for name, value in golden['outputs'].items()}
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'compilers': {name: {'path': str(path), 'sha256': benchmark.sha(path)} for name, path in compilers.items()},
              'guest_mode': 'optimized_debug', 'compiler_host_mode': 'ReleaseFast',
              'affinity': sorted(os.sched_getaffinity(0)), 'jobs': 4,
              'repeats': args.repeats, 'golden_manifest_sha256': benchmark.sha(golden_manifest),
              'cache_compression': compression,
              'method': 'Same source paths and identical edits for both compilers; separate per-compiler frontend, stage and native caches. '
                        'Native caches seeded with validated original cold objects and, when recorded below, completed comparison objects. Fresh intermediate-cache setup is excluded from '
                        'incremental medians. Edits change source length on every sample; baseline/candidate order alternates. '
                        'Wall time and RSS exclude source writes, '
                        'binary hashing, usage and golden/leak validation. Cross-version native/executable audits are diagnostic: '
                        'literal deduplication intentionally changes code generation and layout. Correctness checks are EDA goldens, '
                        'usage and leaks for every build, plus a candidate eager --verify-cache build at 12 copies, rebuilding all '
                        'frontend/IR/optimizer/emission stages and verifying every cached native object and executable. '
                        'All generated modules are imported and every replica is called. Shared host, reserved two physical cores/four threads.',
              'sizes': {}, 'native_seeds': {}, 'records': [], 'summary': {}}

    if saved_setup:
        assert saved_setup['compilers'] == report['compilers'], 'Compiler binaries changed'
        assert saved_setup['cache_compression'] == compression, 'Compression policies changed'
        for key in ['sizes', 'native_seeds', 'records']:
            report[key] = saved_setup[key]
        report['resumed_setup'] = str(root / 'setup-audit-failure.json')
    if extra_report:
        report['additional_native_seed'] = {'path': str(args.candidate_native_extra.resolve()),
                                            'compiler': extra_report['compilers']['candidate'],
                                            'method': 'Only new objects from completed setup; historical edited objects excluded. Checksum validation remains enabled. Setup excluded from timings; no one-build disk measurement.'}

    if prior:
        assert prior['compilers'] == report['compilers'], 'Compiler binaries changed'
        assert prior.get('cache_compression', {'baseline': None, 'candidate': None}) == compression, 'Compression policies changed'
        report['initial_comparison'] = str(root / 'results.json')
        report['method'] = ('Continued warm caches from a completed comparison; no setup is measured. '
                            'Every edit has a new sample number and fresh source bytes. ' + report['method'])
    result_path = root / ('warm-results.json' if prior else 'results.json')

    def save():
        result_path.write_text(json.dumps(report, indent=2) + '\n')

    def validate(binary, output, copies, token):
        environment = dict(env, MYL_CORE_LEAKCHECK='1')
        code, stdout, stderr = benchmark.run([binary], output, environment)
        (output / 'usage.stdout').write_bytes(stdout)
        (output / 'usage.stderr').write_bytes(stderr)
        assert code == 2 and not stdout and stderr.count(b'usage: eda-sch') == copies
        assert stderr.count(token.encode()) == (copies if token == 'usage: eda-sch ' else 1)
        exports = output / 'golden-output'
        exports.mkdir()
        command = [binary, '--model', benchmark.GOLDENS / 'cases/blinky-breakout/model.sexp',
                   '--project-dir', benchmark.GOLDENS / 'projects' / golden['project'],
                   '--out-dir', exports, *golden['flags']]
        code, stdout, stderr = benchmark.run(command, output, environment)
        (output / 'golden.stdout').write_bytes(stdout)
        (output / 'golden.stderr').write_bytes(stderr)
        actual = {str(p.relative_to(exports)): benchmark.sha(p) for p in exports.rglob('*') if p.is_file()}
        assert code == 0 and not stderr and stdout.count(b'eda-sch: ') == copies, (code, stderr[-2000:])
        assert actual == expected, 'golden export hashes changed'
        return 'passed: every replica executed; usage, export hashes and leak check passed'

    def build(copies, source, variant, phase, sample, token):
        directory = root / str(copies) / variant
        output = directory / f'{phase}-{sample}'
        output.mkdir()
        binary = directory / 'program'
        compiler = compilers[variant]
        assert benchmark.sha(compiler) == report['compilers'][variant]['sha256']
        environment = dict(env, MYLANG_CORE_RUNTIME_CACHE=str(directory / 'native'))
        if compression[variant] is not None:
            environment['MYLANG_STAGE_CACHE_COMPRESSION'] = compression[variant]
        command = [compiler, 'build', 'main.my', '-o', binary, '--cache-dir', directory / 'cache', '--report', '--optimize-debug']
        previous_binary = benchmark.sha(binary) if phase == 'eager_verification' else None
        if phase == 'eager_verification':
            command.append('--verify-cache')
            (directory / 'cache/programs-v1').rename(output / 'programs-before-verification')
        metrics = output / 'metrics.json'
        timed = ['/usr/bin/time', '-f', '{"peak_rss_kb":%M,"user_s":%U,"system_s":%S}', '-o', metrics, *command]
        load = Path('/proc/loadavg').read_text().strip()
        existing_objects = set((directory / 'native/units-v1').glob('*.o'))
        start = time.perf_counter()
        code, stdout, stderr = benchmark.run(timed, source, environment)
        seconds = time.perf_counter() - start
        (output / 'build.stdout').write_bytes(stdout)
        (output / 'build.stderr').write_bytes(stderr)
        assert code == 0, (copies, variant, phase, code, stderr[-6000:].decode())
        records = [json.loads(line) for line in stderr.decode().splitlines() if line.startswith('{"version":"cache-report-v1"')]
        assert len(records) == 1
        cache = records[0]
        if compression[variant] is not None:
            assert cache['storage']['compression'] == compression[variant], cache.get('storage')
        if phase.endswith('edit'):
            assert cache['program'] == 'linked'
            assert cache['compiled'] == (3 if phase == 'three_file_edit' else 1), cache
        record = {'copies': copies, 'variant': variant, 'phase': phase, 'sample': sample, 'seconds': seconds,
                  'cache': cache, 'loadavg_before': load, 'loadavg_after': Path('/proc/loadavg').read_text().strip(),
                  'command': [str(x) for x in command], 'cwd': str(source),
                  'new_objects': [str(p) for p in sorted(set((directory / 'native/units-v1').glob('*.o')) - existing_objects)],
                  'binary_sha256': benchmark.sha(binary), **json.loads(metrics.read_text())}
        report['records'].append(record)
        save()
        record['execution_check'] = validate(binary, output, copies, token)
        if phase == 'eager_verification':
            assert cache['verified'] == cache['units'] and cache['compiled'] == 0, cache
            assert cache['program'] == 'linked', cache
            assert record['binary_sha256'] == previous_binary, 'Eager and incremental executables differ'
            record['eager_native_and_executable_check'] = 'passed: every native unit verified; executable byte-identical'
        if phase == 'setup' and args.capture_setup_cache:
            # The native seed contains exactly the original required units;
            # ensure setup used every one and produced no additional objects.
            assert cache['compiled'] == 0 and cache['reused'] == cache['units']
            assert cache['units'] == report['native_seeds'][f'{copies}/{variant}']['unit_object_count']
            subprocess.run(['sync', '-f', directory / 'cache'], check=True)
            components = {p.name: capacity.disk_usage(p) for p in (directory / 'cache').iterdir() if p.is_dir()}
            components['native'] = capacity.disk_usage(directory / 'native')
            totals = [capacity.disk_usage(directory / 'cache'), components['native']]
            record['setup_disk'] = {
                'method': 'One build with empty frontend/stage/program caches and a validated seed containing exactly the required native objects; measured before any edits. Source, output binary and logs excluded.',
                'components': components,
                'total': {key: sum(row[key] for row in totals) for key in totals[0]},
            }
        save()
        print(copies, variant, phase, sample, f'{seconds:.3f}s', f'{record["peak_rss_kb"] / 1048576:.3f}GiB',
              cache.get('stages', {}).get('lowering') if cache.get('stages') else None, flush=True)
        return record

    for copies in args.copies:
        source = root / str(copies) / 'source'
        reused_setup = saved_setup and str(copies) in saved_setup['sizes']
        if reused_setup:
            assert {r['variant'] for r in saved_setup['records'] if r['copies'] == copies} == set(compilers)
        else:
            report['sizes'][str(copies)] = prior['sizes'][str(copies)] if prior else benchmark.generate(source, copies, seed_files)
        print('GENERATED', copies, report['sizes'][str(copies)]['physical_lines'], flush=True)
        for variant in compilers:
            native = root / str(copies) / variant / 'native'
            if prior or reused_setup:
                assert native.is_dir() and (native.parent / 'cache').is_dir()
                if prior:
                    report['native_seeds'][f'{copies}/{variant}'] = prior['native_seeds'][f'{copies}/{variant}']
                continue
            native.mkdir(parents=True)
            seed_record = next(r for r in seed_report['records'] if (r['copies'], r['mode'], r['phase']) == (copies, 'optimized_debug', 'cold'))
            previous = args.native_seed / str(copies) / 'optimized_debug'
            report['native_seeds'][f'{copies}/{variant}'] = benchmark.copy_native_seed(
                previous / 'native', native, previous / 'cold-0.metrics.json', seed_record['cache']['units'])
            if variant == 'candidate' and extra_report:
                records = [r for r in extra_report['records'] if r['copies'] == copies and r['variant'] == 'candidate']
                assert records and all(r.get('execution_check') for r in records)
                previous = args.candidate_native_extra / str(copies) / 'candidate/native'
                setup = next(r for r in records if r['phase'] == 'setup')
                report['native_seeds'][f'{copies}/{variant}/extra'] = copy_setup_objects(previous, native, setup)
        save()
        paths = [source / 'c000/src/main.my', source / 'c000/src/support_strs.my', source / 'c001/src/support_strs.my']
        if prior:
            originals = []
            for path in paths:
                relative = path.relative_to(source)
                prefix, *parts = relative.parts
                text = (benchmark.SEED / Path(*parts)).read_text()
                text = re.sub(r'(?m)^(import )src\.', rf'\g<1>{prefix}.src.', text)
                if parts == ['src', 'main.my']:
                    text = text.replace('func main(', 'public func run_copy(')
                originals.append(text)
        else:
            originals = [p.read_text() for p in paths]
        token = 'usage: eda-sch '
        phases = ['entry_edit', 'helper_edit', 'three_file_edit']
        if not prior and not reused_setup:
            phases.insert(0, 'setup')
        for phase in phases:
            first = 1 + max(r['sample'] for r in prior['records'] if (r['copies'], r['phase']) == (copies, phase)) if prior else 0
            for sample in range(first, first + (1 if phase == 'setup' else args.repeats)):
                if phase in ('entry_edit', 'three_file_edit'):
                    token = f'usage: eda-sch-{phase[0]}{sample:03d}' + 'x' * sample + ' '
                    paths[0].write_text(originals[0].replace('usage: eda-sch ', token))
                if phase in ('helper_edit', 'three_file_edit'):
                    before = 'return c >= 65 and c <= 90'
                    padding = ' ' * (sample + 1)
                    after = f'return (c >= 65 and c <= 90) or{padding}c == {192 + sample + (8 if phase == "three_file_edit" else 0)}'
                    paths[1].write_text(originals[1].replace(before, after))
                    if phase == 'three_file_edit':
                        paths[2].write_text(originals[2].replace(before, after))
                order = list(compilers) if sample % 2 == 0 else list(reversed(compilers))
                results = [build(copies, source, variant, phase, sample, token) for variant in order]
                by_variant = {r['variant']: r for r in results}
                def diagnostic(operation):
                    try:
                        return {'status': 'identical under audit rules', 'details': operation()}
                    except AssertionError as error:
                        return {'status': 'cross-version difference; not a correctness pass', 'details': str(error)}
                audit = (diagnostic(lambda: object_audit.compare(by_variant['baseline']['new_objects'], by_variant['candidate']['new_objects']))
                         if phase != 'setup' else {'status': 'setup creates different native object inventories'})
                identical = results[0]['binary_sha256'] == results[1]['binary_sha256']
                binary_check = diagnostic(lambda: binary_audit.compare(by_variant['baseline']['command'][4], by_variant['candidate']['command'][4]))
                for result in results:
                    result['paired_binary_identical'] = identical
                    result['paired_native_audit'] = audit
                    result['paired_executable_audit'] = binary_check
                save()
        if copies == 12:
            verification_sample = (1 + max(r['sample'] for r in prior['records']
                                          if r['copies'] == copies and r['phase'] == 'eager_verification')) if prior else 0
            build(copies, source, 'candidate', 'eager_verification', verification_sample, token)
        for variant in compilers:
            report['summary'][f'{copies}/{variant}'] = {}
            for phase in ['entry_edit', 'helper_edit', 'three_file_edit']:
                records = [r for r in report['records'] if (r['copies'], r['variant'], r['phase']) == (copies, variant, phase)]
                report['summary'][f'{copies}/{variant}'][phase] = {
                    'median_s': statistics.median(r['seconds'] for r in records),
                    'min_s': min(r['seconds'] for r in records),
                    'max_s': max(r['seconds'] for r in records),
                    'median_peak_rss_gib': statistics.median(r['peak_rss_kb'] / 1048576 for r in records),
                    'median_stages_s': {
                        stage: statistics.median(r['cache']['stages']['nanoseconds'][stage] / 1e9 for r in records)
                        for stage in ['frontend', 'lowering', 'optimizer', 'emission', 'native']},
                    'samples_s': [r['seconds'] for r in records]}
        save()
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    save()


if __name__ == '__main__':
    main()
