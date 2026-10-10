#!/usr/bin/env python3
"""Measure fresh incremental edits against a completed benchmark's existing caches."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import statistics
import time

import benchmark


USAGE = re.compile(r'usage: eda-sch-[a-z]{3}\d{3} ')
PREDICATE = re.compile(r'(?m)^    return \(c >= 65 and c <= 90\) or c == (\d{3})$')


def source_snapshot(source):
    files = sorted(source.rglob('*.my'))
    return {'project_modules': len(files),
            'physical_lines': sum(len(path.read_text().splitlines()) for path in files),
            'source_sha256': {str(path.relative_to(source)): benchmark.sha(path) for path in files}}


def edit_entry(text, token):
    assert len(USAGE.findall(text)) == 1, 'expected one existing benchmark usage token'
    updated, count = USAGE.subn(token, text)
    assert count == 1 and updated != text
    assert len(updated.encode()) == len(text.encode()), 'entry edit changed source length'
    return updated


def edit_predicate(text, byte):
    assert 128 <= byte <= 255, 'predicate must remain outside ASCII and inside a byte'
    assert len(PREDICATE.findall(text)) == 1, 'expected one existing extended-byte predicate'
    updated, count = PREDICATE.subn(lambda match: match.group(0)[:-3] + str(byte), text)
    assert count == 1 and updated != text
    assert len(updated.encode()) == len(text.encode()), 'helper edit changed source length'
    return updated


def validate(binary, directory, output, copies, token, env, golden, expected):
    environment = dict(env, MYL_CORE_LEAKCHECK='1')
    code, stdout, stderr = benchmark.run([binary], directory, environment)
    (output / 'usage.stdout').write_bytes(stdout)
    (output / 'usage.stderr').write_bytes(stderr)
    assert code == 2 and not stdout
    assert stderr.count(b'usage: eda-sch') == copies, 'not every replica printed usage'
    assert stderr.count(token.encode()) == 1, 'edited entry did not print its new token once'
    exports = output / 'golden-output'
    exports.mkdir()
    command = [binary, '--model', benchmark.GOLDENS / 'cases/blinky-breakout/model.sexp',
               '--project-dir', benchmark.GOLDENS / 'projects' / golden['project'],
               '--out-dir', exports, *golden['flags']]
    code, stdout, stderr = benchmark.run(command, directory, environment)
    (output / 'golden.stdout').write_bytes(stdout)
    (output / 'golden.stderr').write_bytes(stderr)
    actual = {str(path.relative_to(exports)): benchmark.sha(path)
              for path in exports.rglob('*') if path.is_file()}
    assert code == 0 and not stderr, (code, stderr[-2000:])
    assert stdout.count(b'eda-sch: ') == copies, 'not every replica exported the golden'
    assert actual == expected, 'export golden mismatch'
    return {'execution_check': 'passed: all replicas ran; usage verified; export hashes match; leak check enabled',
            'binary_bytes': binary.stat().st_size, 'binary_sha256': benchmark.sha(binary),
            'golden_sha256': actual}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True, help='Completed benchmark output root')
    parser.add_argument('--output', type=Path, required=True, help='Fresh result root; source and caches remain in --input')
    parser.add_argument('--copies', type=int, nargs='+', choices=[12, 32], default=[12, 32])
    parser.add_argument('--repeats', type=int, choices=range(1, 5), default=3,
                        help='One to four samples; helper byte ranges must stay disjoint')
    args = parser.parse_args()
    input_root = args.input.resolve()
    previous_path = input_root / 'results.json'
    previous = json.loads(previous_path.read_text())
    assert previous.get('completed_utc'), 'wait until the input benchmark has completed'
    assert len(set(args.copies)) == len(args.copies), 'duplicate copy count'
    assert previous['guest_modes']['optimized_debug'] == ['--optimize-debug']
    compiler = Path(previous['compiler']).resolve()
    assert benchmark.sha(compiler) == previous['compiler_sha256'], 'input compiler binary changed'
    fixtures = {}
    for copies in args.copies:
        source = input_root / str(copies) / 'source'
        directory = input_root / str(copies) / 'optimized_debug'
        assert all((directory / name).exists() for name in ('cache', 'native', 'program'))
        entry = source / 'c000/src/main.my'
        helper = source / 'c000/src/support_strs.my'
        helper2 = source / 'c001/src/support_strs.my'
        assert USAGE.findall(entry.read_text()) == ['usage: eda-sch-few002 ']
        assert PREDICATE.findall(helper.read_text()) == [str(202 if copies == 12 else 234)]
        assert PREDICATE.findall(helper2.read_text()) == ['202']
        if copies == 32:
            assert 'return bench_dependency_002(c)' in helper.read_text()
            assert 'public func bench_dependency_002(c: int) -> bool:' in helper.read_text()
        fixtures[copies] = (source, directory, entry, helper, helper2)
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root / 'tmp').mkdir()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    env.update(MYLANG_JOBS='4', TMPDIR=str(root / 'tmp'))
    memory_limit = previous.get('host_memory_limit', 'default')
    if not memory_limit.startswith('default'):
        env['MYLANG_HOST_MEMORY_LIMIT'] = memory_limit
    manifest = benchmark.GOLDENS / 'manifest.json'
    golden = next(case for case in json.loads(manifest.read_text())['cases'] if case['id'] == 'blinky-breakout')
    expected = {name: value['sha256'] for name, value in golden['outputs'].items()}
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'input': str(input_root), 'input_results_sha256': benchmark.sha(previous_path),
              'compiler': str(compiler), 'compiler_sha256': previous['compiler_sha256'],
              'compiler_host_mode': previous['compiler_host_mode'],
              'guest_modes': {'optimized_debug': ['--optimize-debug']},
              'jobs': 4, 'affinity': sorted(os.sched_getaffinity(0)),
              'host_memory_limit': memory_limit, 'repeats_per_edit': args.repeats,
              'goldens': str(benchmark.GOLDENS), 'golden_manifest_sha256': benchmark.sha(manifest),
              'method': 'Incremental-only continuation of completed fixtures using the identical compiler, native runtime, '
                        'frontend, LLVM and native caches. Same-length fresh entry strings and byte predicates; '
                        'reachable dependency declarations preserved. Every build must link exactly one or three changed '
                        'native units. GNU time wall/RSS excludes source editing, hashes and all-replica golden/leak validation.',
              'sources_before': {}, 'sources_after': {}, 'records': [], 'summary': {}}

    def save():
        (root / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

    def measured_build(copies, phase, sample, edits, token):
        source, directory, *_ = fixtures[copies]
        output = root / str(copies) / f'{phase}-{sample}'
        output.mkdir(parents=True)
        changes = {}
        for path, updated in edits.items():
            before = path.read_bytes()
            relative = str(path.relative_to(source))
            assert before != updated.encode() and len(before) == len(updated.encode())
            changes[relative] = {'before_sha256': benchmark.sha(path), 'before_bytes': len(before)}
            path.write_text(updated)
            changes[relative].update(after_sha256=benchmark.sha(path), after_bytes=path.stat().st_size)
        assert benchmark.sha(compiler) == report['compiler_sha256']
        environment = dict(env, MYLANG_CORE_RUNTIME_CACHE=str(directory / 'native'))
        command = [compiler, 'build', 'main.my', '-o', directory / 'program',
                   '--cache-dir', directory / 'cache', '--report', '--optimize-debug']
        metrics = output / 'metrics.json'
        wrapped = ['/usr/bin/time', '-f', '{"peak_rss_kb":%M,"user_s":%U,"system_s":%S}', '-o', metrics, *command]
        load = Path('/proc/loadavg').read_text().strip()
        start = time.perf_counter()
        code, stdout, stderr = benchmark.run(wrapped, source, environment)
        seconds = time.perf_counter() - start
        (output / 'build.stdout').write_bytes(stdout)
        (output / 'build.stderr').write_bytes(stderr)
        assert code == 0, (copies, phase, code, stderr[-6000:].decode())
        caches = [json.loads(line) for line in stderr.decode().splitlines()
                  if line.startswith('{"version":"cache-report-v1"')]
        assert len(caches) == 1
        cache = caches[0]
        stages = cache.pop('stages', None)
        assert cache['program'] == 'linked', 'unexpected replay'
        assert cache['compiled'] == len(edits), ('expected exactly one native unit per changed file', cache)
        assert cache['reused'] + cache['compiled'] == cache['units']
        record = {'copies': copies, 'mode': 'optimized_debug', 'phase': phase, 'sample': sample,
                  'seconds': seconds, 'cache': cache, 'stages': stages, 'changed_sources': changes,
                  'entry_token': token,
                  'physical_lines': report['sources_before'][str(copies)]['physical_lines'],
                  'project_modules': report['sources_before'][str(copies)]['project_modules'],
                  'command': [str(value) for value in command], 'cwd': str(source),
                  'environment': {key: value for key, value in environment.items() if key.startswith('MYLANG_')},
                  'affinity': sorted(os.sched_getaffinity(0)), 'loadavg_before': load,
                  'loadavg_after': Path('/proc/loadavg').read_text().strip(), **json.loads(metrics.read_text())}
        report['records'].append(record)
        save()
        record.update(validate(directory / 'program', directory, output, copies, token, env, golden, expected))
        assert benchmark.sha(compiler) == report['compiler_sha256']
        save()
        print(copies, phase, sample, f'{seconds:.3f}s', cache, flush=True)

    save()
    try:
        for copies in args.copies:
            source, _, entry, helper, helper2 = fixtures[copies]
            report['sources_before'][str(copies)] = source_snapshot(source)
            backups = root / str(copies) / 'source-before'
            for path in (entry, helper, helper2):
                saved = backups / path.relative_to(source)
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_bytes(path.read_bytes())
            for sample in range(args.repeats):
                token = f'usage: eda-sch-rep{sample:03d} '
                measured_build(copies, 'entry_edit', sample, {entry: edit_entry(entry.read_text(), token)}, token)
            for sample in range(args.repeats):
                measured_build(copies, 'helper_edit', sample,
                               {helper: edit_predicate(helper.read_text(), 211 + sample)}, token)
            for sample in range(args.repeats):
                token = f'usage: eda-sch-rpt{sample:03d} '
                edits = {entry: edit_entry(entry.read_text(), token),
                         helper: edit_predicate(helper.read_text(), 215 + sample),
                         helper2: edit_predicate(helper2.read_text(), 215 + sample)}
                measured_build(copies, 'three_file_edit', sample, edits, token)
            report['sources_after'][str(copies)] = source_snapshot(source)
            report['summary'][str(copies)] = {}
            for phase in ('entry_edit', 'helper_edit', 'three_file_edit'):
                samples = [record['seconds'] for record in report['records']
                           if (record['copies'], record['phase']) == (copies, phase)]
                report['summary'][str(copies)][phase] = {'optimized_debug': {
                    'median_s': statistics.median(samples), 'min_s': min(samples),
                    'max_s': max(samples), 'samples_s': samples}}
            save()
    except Exception as error:
        report['failed_utc'] = datetime.now(timezone.utc).isoformat()
        report['failure'] = repr(error)
        save()
        raise
    assert benchmark.sha(compiler) == report['compiler_sha256']
    assert benchmark.sha(previous_path) == report['input_results_sha256']
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    print('COMPLETE', root / 'results.json', flush=True)


if __name__ == '__main__':
    main()
