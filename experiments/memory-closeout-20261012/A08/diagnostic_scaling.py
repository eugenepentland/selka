#!/usr/bin/env python3
"""Bounded frontend/Core diagnostic scaling, excluding native generation and linking.

Run only inside an A09-approved exclusive timing lease. Each command uses fresh
in-process frontend/Core state; dump-ir does not enable persisted stage caches.
Operating-system file caches are not flushed. This reports one exploratory sample
per size, not a runtime speedup or a whole-build comparison.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

import qualify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, required=True)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--default-zero', action='store_true')
    parser.add_argument('--source-manifest', type=Path, default=Path(__file__).with_name('diagnostic-sources.json'))
    args = parser.parse_args()
    manifest = json.loads(args.source_manifest.read_text())
    if manifest['generator_sha256'] != qualify.digest(qualify.__file__):
        parser.error('Frozen source generator changed; review and freeze a new manifest first')
    expected_cases = {row['name']: row for row in manifest['cases']}
    args.compiler = args.compiler.resolve()
    args.work = args.work.resolve()
    args.output = args.output.resolve()
    if args.work.exists() or args.output.exists():
        parser.error('Choose unused work and evidence directories')
    if args.cpu not in os.sched_getaffinity(0):
        parser.error('Requested CPU is not allowed')
    args.work.mkdir(parents=True)
    args.output.mkdir(parents=True)
    env = dict(os.environ)
    for name in ('MYLANG_FRONTEND_CACHE', 'MYLANG_TEST_SHARED_CACHE', 'SOURCE_DATE_EPOCH', 'ZERO_AR_DATE'):
        env.pop(name, None)
    env.update(MYLANG_COMPILER_SHARED_CACHE=str(args.work / 'shared'),
               MYLANG_CORE_RUNTIME_CACHE=str(args.work / 'objects'))
    report = dict(compiler=str(args.compiler), compiler_sha256=qualify.digest(args.compiler),
                  compiler_revision=args.source_revision,
                  harness_sha256=qualify.digest(__file__), generator_sha256=qualify.digest(qualify.__file__),
                  source_manifest_sha256=qualify.digest(args.source_manifest),
                  command_scope='dump-ir --facts: parsing, source checks, ownership validation, Core lowering, release passes, facts and IR formatting/writing; no LLVM, native compilation, guest admission or linking',
                  stage_separation='This command has no per-stage timing report; elapsed covers the complete stated diagnostic scope.',
                  cache_state='Fresh in-process frontend/Core; no persisted stage cache enabled; OS file caches not flushed.',
                  sampling='One exploratory sample per family/size; no speedup claim.',
                  rss_scope='GNU time maximum individual child RSS, not summed process-tree peak.',
                  admission='A09-approved exclusive timing lease supplied by caller; no nested admission.',
                  cpu=args.cpu, allowed_cpus=sorted(os.sched_getaffinity(0)),
                  started_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), cases=[])
    for family in ('modules', 'generics'):
        for size in (16, 64, 128):
            name = f'{family}-{size}'
            project = args.work / name
            sources, expected = qualify.generate(family, size)
            source_hashes = {path: hashlib.sha256(contents.encode()).hexdigest() for path, contents in sources.items()}
            if source_hashes != expected_cases[name]['sources'] or expected != expected_cases[name]['expected_guest_output']:
                raise ValueError('Generated sources differ from frozen manifest: ' + name)
            for path, contents in sources.items():
                qualify.write(project / path, contents)
            ir = args.output / (name + '.ir')
            stderr = args.output / (name + '.stderr')
            rss = args.output / (name + '.rss')
            command = [str(args.compiler), 'dump-ir', str(project / 'main.my'), '--facts']
            if not args.default_zero:
                command.append('--experimental-zero-rc')
            measured = ['/usr/bin/timeout', str(args.timeout), '/usr/bin/time', '-f', '%M', '-o', str(rss),
                        'taskset', '-c', str(args.cpu), *command]
            with ir.open('wb') as stdout, stderr.open('wb') as errors:
                before = time.perf_counter_ns()
                result = subprocess.run(measured, cwd=project, env=env, stdout=stdout, stderr=errors)
                elapsed = time.perf_counter_ns() - before
            text = stderr.read_text()
            outcome = 'diagnostic_completed' if result.returncode == 0 else 'timeout' if result.returncode == 124 else 'source_refusal' if 'error[E_' in text else 'compiler_failure'
            payload = ir.read_bytes()
            compressed = ir.with_suffix('.ir.gz')
            compressed.write_bytes(gzip.compress(payload, mtime=0))
            row = dict(name=name, family=family, size=size, command=command, measured_command=measured,
                       status=result.returncode, outcome=outcome, elapsed_ns=elapsed,
                       max_individual_child_rss_kib=rss.read_text().strip().splitlines()[-1] if rss.exists() else None,
                       sources=source_hashes,
                       source_bytes=sum(len(s.encode()) for s in sources.values()),
                       expected_guest_output=expected, guest_executed=False,
                       ir_sha256=hashlib.sha256(payload).hexdigest(), ir_bytes=len(payload),
                       ir_gzip=compressed.name, stderr=stderr.name)
            ir.unlink()
            report['cases'].append(row)
            report['completed_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            qualify.write(args.output / 'results.json', json.dumps(report, indent=2) + '\n')
            print(json.dumps({key: row[key] for key in ('name', 'status', 'outcome', 'elapsed_ns', 'ir_bytes')}), flush=True)
    raise SystemExit(0 if all(row['status'] == 0 for row in report['cases']) else 1)


if __name__ == '__main__':
    main()
