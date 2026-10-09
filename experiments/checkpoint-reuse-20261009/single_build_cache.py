#!/usr/bin/env python3
"""Measure disk space after exactly one optimized-debug build from empty caches."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time


spec = importlib.util.spec_from_file_location(
    'benchmark', Path(__file__).parents[1] / 'incremental-stages-20261009/benchmark.py')
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


def disk_usage(directory):
    """Record logical bytes and physical allocation, including directory blocks."""
    result = {'allocated_bytes': 0, 'logical_file_bytes': 0, 'files': 0}
    for path in [directory, *directory.rglob('*')]:
        stat = path.stat()
        result['allocated_bytes'] += stat.st_blocks * 512
        if path.is_file():
            result['logical_file_bytes'] += stat.st_size
            result['files'] += 1
    return result


def validate(binary, directory, copies, env):
    env = dict(env, MYL_CORE_LEAKCHECK='1')
    code, stdout, stderr = benchmark.run([binary], directory, env)
    (directory / 'usage.stderr').write_bytes(stderr)
    assert code == 2 and not stdout and stderr.count(b'usage: eda-sch ') == copies
    manifest = json.loads((benchmark.GOLDENS / 'manifest.json').read_text())
    golden = next(c for c in manifest['cases'] if c['id'] == 'blinky-breakout')
    exports = directory / 'golden-output'
    exports.mkdir()
    code, stdout, stderr = benchmark.run([
        binary, '--model', benchmark.GOLDENS / 'cases/blinky-breakout/model.sexp',
        '--project-dir', benchmark.GOLDENS / 'projects' / golden['project'],
        '--out-dir', exports, *golden['flags']], directory, env)
    (directory / 'golden.stdout').write_bytes(stdout)
    (directory / 'golden.stderr').write_bytes(stderr)
    assert code == 0 and not stderr and stdout.count(b'eda-sch: ') == copies
    actual = {str(p.relative_to(exports)): benchmark.sha(p) for p in exports.rglob('*') if p.is_file()}
    assert actual == {name: value['sha256'] for name, value in golden['outputs'].items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--copies', type=int, nargs='+', default=[12, 32])
    parser.add_argument('--jobs', type=int, default=8)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    env = {k: v for k, v in os.environ.items() if not k.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    env['MYLANG_JOBS'] = str(args.jobs)
    seed_files = [x['path'] for x in json.loads(benchmark.DEPENDENCIES.read_text())['inputs']
                  if not x['path'].startswith('@')]
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'compiler': str(compiler), 'compiler_sha256': benchmark.sha(compiler),
              'guest_mode': 'optimized_debug', 'jobs': args.jobs,
              'affinity': sorted(os.sched_getaffinity(0)),
              'method': 'Exactly one build per size. Empty project, semantic, stage, program and native caches; '
                        'no native seed and no source edits. Installed compiler/toolchain is reused. '
                        'Allocated disk bytes include directory blocks; logical file bytes are also recorded. '
                        'Output executable, source, temporary files and measurement logs are excluded from cache totals. '
                        'Disk-capacity experiment on nonreserved CPUs, not a paired timing comparison.',
              'records': []}
    for copies in args.copies:
        directory = root / str(copies)
        source = directory / 'source'
        size = benchmark.generate(source, copies, seed_files)
        cache, native, temporary = [directory / name for name in ('cache', 'native', 'tmp')]
        for path in (cache, native, temporary):
            path.mkdir()
            assert not any(path.iterdir())
        environment = dict(env, MYLANG_CORE_RUNTIME_CACHE=str(native), TMPDIR=str(temporary))
        binary = directory / 'program'
        command = [compiler, 'build', 'main.my', '-o', binary,
                   '--cache-dir', cache, '--report', '--optimize-debug']
        print(f'START {copies}: {size["physical_lines"]} lines, all caches empty', flush=True)
        started = time.perf_counter()
        code, stdout, stderr = benchmark.run(command, source, environment)
        seconds = time.perf_counter() - started
        (directory / 'build.stdout').write_bytes(stdout)
        (directory / 'build.stderr').write_bytes(stderr)
        assert code == 0, (code, stderr[-6000:].decode())
        records = [json.loads(line) for line in stderr.decode().splitlines()
                   if line.startswith('{"version":"cache-report-v1"')]
        assert len(records) == 1
        counts = records[0]
        assert counts['reused'] == 0 and counts['compiled'] == counts['units'] > 0
        assert counts['stages']['lowering']['reused'] == 0
        validate(binary, directory, copies, environment)
        # Settle delayed filesystem allocation before reading st_blocks.
        subprocess.run(['sync', '-f', cache], check=True)
        components = {path.name: disk_usage(path) for path in cache.iterdir() if path.is_dir()}
        components['native'] = disk_usage(native)
        totals = [disk_usage(cache), components['native']]
        record = {'copies': copies, 'size': size, 'build_seconds': seconds,
                  'command': [str(x) for x in command], 'cache_report': counts,
                  'components': components,
                  'total': {key: sum(value[key] for value in totals) for key in totals[0]},
                  'output_executable_bytes': binary.stat().st_size,
                  'binary_sha256': benchmark.sha(binary), 'execution_checks_passed': True}
        report['records'].append(record)
        (root / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'DONE {copies}: {json.dumps(record["total"])}', flush=True)
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    (root / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
