#!/usr/bin/env python3
"""Measure named guest-project edits with real check and forced test commands.

Run directly under one admitted build (qualification) or bounded timing window.
The existing supervisor owns subprocess lineages; this harness owns no admission.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from verification_process import ProcessLimits, run_supervised, wait_owned


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def command(argv, folder, environment):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic_ns()
    with (folder.with_suffix('.stdout')).open('wb') as out, (folder.with_suffix('.stderr')).open('wb') as err:
        child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--child', *argv],
                                 stdout=out, stderr=err, env=environment, start_new_session=True)
        result = wait_owned(child, limits=ProcessLimits(20))
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    return {'argv': argv, 'status': result.returncode, 'complete': result.complete,
            'elapsed_ns': time.monotonic_ns() - started,
            'child_accounted_user_cpu_seconds': after.ru_utime - before.ru_utime,
            'child_accounted_system_cpu_seconds': after.ru_stime - before.ru_stime,
            'memory_scope': 'cohort cumulative RUSAGE_CHILDREN high-water; concurrent aggregate unknown',
            'cohort_child_high_water_rss_bytes': after.ru_maxrss * 1024,
            'stdout_sha256': digest(folder.with_suffix('.stdout')),
            'stderr_sha256': digest(folder.with_suffix('.stderr'))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--compiler-source', required=True, help='Exact compiler source commit, checked by artifact manifest')
    parser.add_argument('--mode', choices=('Debug', 'ReleaseFast'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=40)
    parser.add_argument('--check-only', action='store_true', help='Partial semantic feedback only; native completion unqualified')
    parser.add_argument('--workload', choices=('helper-edit', 'test-only-edit'), default='helper-edit')
    args = parser.parse_args()
    if not 1 <= args.repetitions <= 100:
        parser.error('repetitions must be 1..100')
    output = args.output.resolve()
    if output.exists():
        parser.error('output must be a new private directory')
    output.mkdir(parents=True)
    project = output / 'project'; project.mkdir()
    compiler = args.compiler.resolve()
    zig = Path(os.environ['MYLANG_ZIG']).resolve()
    artifact_manifest_path = compiler.parent.parent / 'manifest.json'
    artifact_manifest = None
    companion_hashes = {}
    if artifact_manifest_path.is_file():
        encoded_manifest = artifact_manifest_path.read_bytes()
        if len(encoded_manifest) > 16 * 1024 * 1024:
            raise RuntimeError('artifact manifest exceeds bound')
        artifact_manifest = json.loads(encoded_manifest)
        for relative, expected in artifact_manifest['files'].items():
            name = Path(relative)
            if name.is_absolute() or '..' in name.parts:
                raise RuntimeError('artifact manifest path escapes prefix')
            actual = (compiler.parent.parent / name).resolve()
            actual.relative_to(compiler.parent.parent)
            observed = digest(actual)
            if observed != expected:
                raise RuntimeError('frozen prefix differs from artifact manifest')
            companion_hashes[str(actual)] = observed
    environment = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=str(output / 'runtime-cache'))
    environment.pop('MYLANG_COMPILER_SHARED_CACHE', None)
    manifest = {'version': 1, 'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'compiler_source': args.compiler_source,
                'harness_sha256': digest(__file__),
                'artifact_manifest_sha256': digest(artifact_manifest_path) if artifact_manifest else None,
                'compiler_source_tree_sha256': artifact_manifest.get('source_tree_sha256') if artifact_manifest else None,
                'companion_file_sha256': companion_hashes,
                'compiler': str(compiler), 'compiler_sha256': digest(compiler), 'compiler_mode': args.mode,
                'zig': str(zig), 'zig_sha256': digest(zig), 'affinity': sorted(os.sched_getaffinity(0)),
                'slot_directory': environment.get('MYLANG_SLOT_DIR'),
                'declared_build_slots': environment.get('MYLANG_BUILD_SLOTS'),
                'admission_kind': environment.get('MYLANG_ADMISSION_KIND'), 'workload': args.workload,
                'cache_tier': 'private project/runtime placement; shared Zig global requested; unapproved tool overrides with private per-link global/local and objects',
                'clock': 'source edit + validation + real check + output checks/report write' if args.check_only else 'source edit + validation + real check + forced two-test command + output checks/report write',
                'scope': 'guest project edit; does not measure Zig compiler-source rebuilding or whole gate',
                'first_feedback_scope': 'completed type/semantic check; visibly partial before two tests',
                'selected_test_names': [] if args.check_only else ['main::test_answer', 'main::test_stable'],
                'check_only': args.check_only, 'rows': []}
    context = {key: value for key, value in manifest.items() if key != 'rows'}
    manifest['run_id'] = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
    manifest['measurement_context'] = hashlib.sha256(json.dumps(context, sort_keys=True).encode()).hexdigest()
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    rows = manifest['rows']
    for index in range(args.repetitions + 1):
        started = time.monotonic_ns()
        value = 42 + index if args.workload == 'helper-edit' else 42
        condition = 'helper.answer() == %d' % value
        if args.workload == 'test-only-edit':
            condition += ' and helper.answer() >= %d' % (-index)
        (project / 'helper.my').write_text('public func answer() -> int:\n    return %d\n' % value)
        (project / 'main.my').write_text('import helper\n\npublic func test_answer() -> bool:\n    return %s\n\npublic func test_stable() -> bool:\n    return 7 * 6 == 42\n\nfunc main() -> int:\n    return 0\n' % condition)
        source_hashes = {path.name: digest(path) for path in sorted(project.glob('*.my'))}
        edit_end = time.monotonic_ns()
        check = command([str(compiler), 'check', str(project / 'main.my'), '--cache-dir=' + str(output / 'frontend-cache')], output / ('sample-%02d-check' % index), environment)
        first_feedback = time.monotonic_ns() - started
        if args.check_only:
            trial = None
            payload = {'passed': 0}
            names = []
            passed = check['status'] == 0 and check['complete']
        else:
            trial = command([str(compiler), 'test', str(project / 'main.my'), '--json', '--force', '--jobs', '1', '--zig', str(zig), '--cache-dir', str(output / 'guest-cache')], output / ('sample-%02d-test' % index), environment)
            payload = json.loads((output / ('sample-%02d-test.stdout' % index)).read_text())
            names = sorted(test['name'] for test in payload['tests'])
            passed = (check['status'] == 0 and trial['status'] == 0 and check['complete'] and trial['complete']
                      and names == manifest['selected_test_names'] and payload['passed'] == 2
                      and payload['cached'] == payload['failed'] == payload['skipped'] == 0)
        row = {'index': index, 'cache_tier': 'cold-project-runtime' if index == 0 else 'warm-unique-edit',
               'native_cache_reasons': sorted({r.get('cache', {}).get('reason', 'unknown') for r in payload.get('tests', [])}),
               'effective_native_tier': 'not executed' if args.check_only else ('uncacheable private per-link objects/global/local' if any(r.get('cache', {}).get('reason') == 'uncacheable-toolchain' for r in payload.get('tests', [])) else 'see exact native work/reason records'),
               'source_sha256': source_hashes, 'edit_validation_ns': edit_end - started,
               'first_feedback_ns': first_feedback, 'check': check, 'test': trial, 'selected_tests': len(names), 'completed_successful_tests': payload.get('passed', 0),
               'passed': passed, 'measurement_kind': 'isolated' if os.environ.get('MYLANG_ADMISSION_KIND') == 'timing' else 'operational'}
        rows.append(row)
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        row['loop_elapsed_ns'] = time.monotonic_ns() - started
        with (output / 'rows.jsonl').open('a') as stream: stream.write(json.dumps(row, sort_keys=True) + '\n')
        if not passed:
            raise RuntimeError('real compiler/test verdict or exact fresh inventory disagrees')
    if digest(__file__) != manifest['harness_sha256']:
        raise RuntimeError('collector source changed during cohort')
    if artifact_manifest and (digest(artifact_manifest_path) != manifest['artifact_manifest_sha256'] or any(digest(path) != value for path, value in companion_hashes.items())):
        raise RuntimeError('artifact manifest or companion files changed during cohort')
    if digest(compiler) != manifest['compiler_sha256'] or digest(zig) != manifest['zig_sha256']:
        raise RuntimeError('frozen tools changed during cohort')
    warm = rows[1:]
    values = sorted(row['loop_elapsed_ns'] for row in warm)
    feedback = sorted(row['first_feedback_ns'] for row in warm)
    import statistics
    summary = {'repetitions': len(warm), 'median_ns': statistics.median(values),
               'empirical_p95_ns': values[math.ceil(0.95 * len(values)) - 1],
               'first_feedback_empirical_p95_ns': feedback[math.ceil(0.95 * len(feedback)) - 1],
               'targets': {'feedback_5s': max(feedback) <= 5_000_000_000,
                           'completion_empirical_p95_15s': None if args.check_only else values[math.ceil(0.95 * len(values)) - 1] <= 15_000_000_000},
               'all_completed': all(row['passed'] for row in rows),
               'scope': manifest['scope'], 'qualification': 'empirical cohort only; no stable tail inference or broader compiler-edit claim'}
    manifest['summary'] = summary
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--child']:
        raise SystemExit(run_supervised(sys.argv[2:], dict(os.environ)))
    main()
