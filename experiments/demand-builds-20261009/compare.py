#!/usr/bin/env python3
"""Paired edited-build comparison on identical reachable EDA replicas."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import statistics
import time
import object_audit


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


benchmark = module('benchmark', Path(__file__).parents[1] / 'incremental-stages-20261009/benchmark.py')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--native-seed', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--copies', type=int, nargs='+', default=[12, 32])
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root / 'tmp').mkdir()
    compilers = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    env = {k: v for k, v in os.environ.items() if not k.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    env.update(MYLANG_JOBS='4', TMPDIR=str(root / 'tmp'))
    seed_report = json.loads((args.native_seed / 'results.json').read_text())
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
              'method': 'Same source paths and identical edits for both compilers; separate per-compiler frontend, stage and native caches. '
                        'Native caches seeded only with validated original cold objects. Fresh intermediate-cache setup is excluded from '
                        'incremental medians. Edits change source length on every sample; baseline/candidate order alternates. '
                        'Wall time and RSS exclude source writes, '
                        'binary hashing, usage and golden/leak validation. Changed native objects must have identical instructions, '
                        'literal values/references, DWARF and trap descriptors; only literal-pool ordering/alignment may differ. '
                        'All generated modules are imported and every replica is called. Shared host, reserved two physical cores/four threads.',
              'sizes': {}, 'native_seeds': {}, 'records': [], 'summary': {}}

    def save():
        (root / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

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
        command = [compiler, 'build', 'main.my', '-o', binary, '--cache-dir', directory / 'cache', '--report', '--optimize-debug']
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
        save()
        print(copies, variant, phase, sample, f'{seconds:.3f}s', f'{record["peak_rss_kb"] / 1048576:.3f}GiB',
              cache.get('stages', {}).get('lowering') if cache.get('stages') else None, flush=True)
        return record

    for copies in args.copies:
        source = root / str(copies) / 'source'
        report['sizes'][str(copies)] = benchmark.generate(source, copies, seed_files)
        print('GENERATED', copies, report['sizes'][str(copies)]['physical_lines'], flush=True)
        for variant in compilers:
            native = root / str(copies) / variant / 'native'
            native.mkdir(parents=True)
            prior = next(r for r in seed_report['records'] if (r['copies'], r['mode'], r['phase']) == (copies, 'optimized_debug', 'cold'))
            previous = args.native_seed / str(copies) / 'optimized_debug'
            report['native_seeds'][f'{copies}/{variant}'] = benchmark.copy_native_seed(
                previous / 'native', native, previous / 'cold-0.metrics.json', prior['cache']['units'])
        save()
        paths = [source / 'c000/src/main.my', source / 'c000/src/support_strs.my', source / 'c001/src/support_strs.my']
        originals = [p.read_text() for p in paths]
        token = 'usage: eda-sch '
        for phase in ['setup', 'entry_edit', 'helper_edit', 'three_file_edit']:
            for sample in range(1 if phase == 'setup' else args.repeats):
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
                audit = object_audit.compare(by_variant['baseline']['new_objects'], by_variant['candidate']['new_objects'])
                identical = results[0]['binary_sha256'] == results[1]['binary_sha256']
                if not identical:
                    assert audit, 'executable differs without any changed native object'
                for result in results:
                    result['paired_binary_identical'] = identical
                    result['paired_native_audit'] = audit
                save()
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
