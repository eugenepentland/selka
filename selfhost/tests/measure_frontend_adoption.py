#!/usr/bin/env python3
"""Isolated, correctness-checked frontend workflow and parser transport measurement.

Requires a prebuilt ReleaseFast host, verified packages and exclusive timing
admission held by the coordinator. Never run alongside a gate. Cold means an
empty application cache or empty component artifact store, not a cold seed or
machine. The native coordinator is the only component compilation driver.
"""
import argparse
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import statistics
import subprocess
import tempfile
import threading
import time

from run_frontend_qualification import (FRONTENDS, PACKAGES, ROOT, FIXTURES,
                                       OUTPUT_LIMIT, ADDRESS_SPACE_BUDGET, copy_sources, digest, environment,
                                       packages, process_limits, profile_sources, require)


def execute(argv, env, cwd, timeout=180):
    """Wait directly for exit; deadline enforcement does not quantize samples."""
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        process = subprocess.Popen([str(a) for a in argv], env=env, cwd=cwd,
                                   stdout=stdout, stderr=stderr, preexec_fn=process_limits,
                                   start_new_session=True)
        expired = threading.Event()
        def terminate():
            if process.poll() is None:
                expired.set()
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        watchdog = threading.Timer(timeout, terminate)
        watchdog.daemon = True
        watchdog.start()
        try:
            process.wait()
        finally:
            watchdog.cancel()
            watchdog.join()
            if process.poll() is None:
                terminate()
                process.wait()
        if expired.is_set():
            raise subprocess.TimeoutExpired(argv, timeout)
        stdout.seek(0)
        stderr.seek(0)
        return process.returncode, stdout.read(OUTPUT_LIMIT), stderr.read(OUTPUT_LIMIT)


def sample(command, env, cwd, expected=0, output=None):
    start = time.perf_counter_ns()
    result = execute(command, env, cwd, timeout=600)
    elapsed = time.perf_counter_ns() - start
    require(result[0] == expected, f'measured command failed: {command!r}: {result!r}')
    require(output is None or result[1] == output, 'measured command output changed')
    return elapsed, result


def distribution(samples):
    return {'samples_ns': samples, 'median_ns': statistics.median(samples),
            'min_ns': min(samples), 'max_ns': max(samples)}


def transport(args, work, empty):
    rows = []
    bodies = {'tiny': b'func main() -> int:\n    return 0\n',
              'comments64k': b'#' + b' ' * 65498 + b'\nfunc main() -> int:\n    return 0\n',
              'nodes': ''.join(f'func f{i}() -> int:\n    return {i}\n\n' for i in range(700)).encode() +
                       b'func main() -> int:\n    return 0\n'}
    if args.large_profile:
        bodies.update({name: body for name, body in profile_sources().items()
                       if name in ('boundary.my', 'profile_dense.my', 'profile_comments.my', 'profile_nested.my')})
    for name, body in bodies.items():
        source = work / f'{name}.my'
        source.write_bytes(body)
        command = [args.compiler, 'dump-syntax', source]
        reference = None
        for mode in args.modes:
            env = environment(mode, args.component_dir, empty)
            env['MYL_CORE_LEAKCHECK'] = '0'
            env['MYLANG_LEXER_MODE'] = 'reference'  # Isolate the parser boundary.
            _, baseline = sample(command, env, work)
            require(not baseline[2] and baseline[1].startswith(b'SLKAST01'), 'invalid syntax transport baseline')
            if reference is None:
                reference = baseline
            require(baseline == reference, 'parser transport differs from reference')
            samples = []
            for _ in range(args.iterations):
                elapsed, actual = sample(command, env, work, output=baseline[1])
                require(actual == baseline, 'parser transport is nonrepeatable')
                samples.append(elapsed)
            rows.append({'source': name, 'source_bytes': len(body), 'reply_bytes': len(baseline[1]),
                         'serialized_ast_values': int.from_bytes(baseline[1][8:12], 'little'),
                         'mode': mode, 'scope': 'complete CLI dump-syntax; lexer reference; parser mode selected',
                         **distribution(samples)})
    return rows


def application(args, work, empty):
    source = work / 'application'
    copy_sources(source)
    helper = source / 'helper.my'
    original = helper.read_text()
    rows = []
    for mode in args.modes:
        helper.write_text(original)
        env = environment(mode, args.component_dir, empty)
        env['MYL_CORE_LEAKCHECK'] = '0'
        cache = work / f'application-cache-{mode}'
        output = work / 'application-program'
        command = [args.compiler, 'build', source / 'main.my', '--project', '-o', output,
                   '--cache-dir', cache, f'--zig={args.zig}', '--report']
        elapsed, cold = sample(command, env, work, output=b'')
        require(execute([output], env, work) == (7, b'', b''), 'cold built program changed behavior')
        rows.append({'mode': mode, 'scope': 'empty application cache; shared runtime/toolchain caches may be warm',
                     'phase': 'cold', 'elapsed_ns': elapsed, 'cache_evidence': cold[2].decode()})
        samples = []
        for _ in range(args.iterations):
            elapsed, warm = sample(command, env, work, output=b'')
            require(execute([output], env, work) == (7, b'', b''), 'warm built program changed behavior')
            samples.append(elapsed)
        rows.append({'mode': mode, 'phase': 'warm', 'scope': 'identical application build command and populated cache',
                     'cache_evidence': warm[2].decode(), **distribution(samples)})
        edit_samples = []
        for value in range(8, 8 + args.edit_iterations):
            helper.write_text(original.replace('return 7', f'return {value}'))
            elapsed, edited = sample(command, env, work, output=b'')
            require(execute([output], env, work) == (value, b'', b''), 'source edit did not reach native artifact')
            edit_samples.append(elapsed)
        rows.append({'mode': mode, 'phase': 'edit', 'scope': 'imported function body edit through native application build',
                     'cache_evidence': edited[2].decode(), **distribution(edit_samples)})
    helper.write_text(original)
    return rows


def components(args, work):
    source = work / 'coordinator-source'
    (source / 'selfhost').mkdir(parents=True)
    shutil.copyfile(args.source_root / 'selfhost/component-seed.json', source / 'selfhost/component-seed.json')
    shutil.copytree(args.source_root / 'selfhost/components', source / 'selfhost/components', symlinks=True)
    cache = work / 'coordinator-cache'
    cache.mkdir()
    shared = args.seed_cache.resolve()
    require(shared.is_dir(), 'qualified shared seed store absent')
    (cache / 'seeds').symlink_to(shared, target_is_directory=True)
    installation = work / 'coordinator-install'
    command = [args.builder, '--root', source, '--zig', args.zig, '--cache-dir', cache,
               '--install-dir', installation]
    host_before = digest(args.compiler)
    env = dict(os.environ, MYLANG_LEXER_MODE='reference', MYLANG_PARSER_MODE='reference', MYL_CORE_LEAKCHECK='0')
    elapsed, _ = sample(command, env, work)
    before = packages(installation, args.frontend_schema)
    rows = [{'phase': 'cold-artifacts', 'scope': 'native coordinator verifies reused seed and builds/installs all four packages',
             'elapsed_ns': elapsed, 'packages': before}]
    samples = []
    for _ in range(args.coordinator_iterations):
        elapsed, _ = sample(command, env, work)
        require(packages(installation, args.frontend_schema) == before, 'warm coordinator changed package identity')
        samples.append(elapsed)
    rows.append({'phase': 'warm', 'scope': 'native coordinator verifies qualified seed and existing package receipts/install',
                 **distribution(samples)})
    edited = source / 'selfhost/components/parser_pilot/full_resource.my'
    text = edited.read_text()
    marker = '    mut count = 1\n'
    require(text.count(marker) == 1, 'coordinator edit marker ambiguous')
    edited.write_text(text.replace(marker, marker +
                     '    if tag == "pilot_edit_marker":\n        return Signature(typed=False, owner=False, arguments=0, variadic=False)\n'))
    elapsed, _ = sample(command, env, work)
    after = packages(installation, args.frontend_schema)
    require(before['parser-pilot']['key'] != after['parser-pilot']['key'] and
            before['parser-pilot']['sha256'] != after['parser-pilot']['sha256'], 'component edit did not change executable identity')
    require(all(before[n] == after[n] for n in PACKAGES if n != 'parser-pilot'), 'unrelated component identity changed')
    require(digest(args.compiler) == host_before, 'component edit rebuilt host')
    # Timing ends before independent output comparison. The changed producer is
    # still required to yield the reference AST through the installed boundary.
    source_case = work / 'edited-comparison.my'
    source_case.write_text('func main() -> int:\n    return 7\n')
    empty = work / 'coordinator-empty-path'
    empty.mkdir()
    reference = execute([args.compiler, 'dump-syntax', source_case], environment('reference', installation, empty), work)
    for mode in args.modes:
        actual = execute([args.compiler, 'dump-syntax', source_case], environment(mode, installation, empty), work)
        require(actual == reference and actual[0] == 0, 'edited native coordinator package changed AST')
    rows.append({'phase': 'parser-edit', 'scope': 'source edit through coordinator qualification/snapshot/compile/install; three other receipts reused',
                 'elapsed_ns': elapsed, 'before': before['parser-pilot'], 'after': after['parser-pilot'],
                 'host_sha256_unchanged': host_before})
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--component-dir', type=Path, required=True)
    ap.add_argument('--builder', type=Path, required=True)
    ap.add_argument('--source-root', type=Path, default=ROOT)
    ap.add_argument('--zig', type=Path, required=True)
    ap.add_argument('--seed-cache', type=Path, default=Path.home() / '.cache/mylang/components/seeds')
    ap.add_argument('--iterations', type=int, default=20)
    ap.add_argument('--edit-iterations', type=int, default=5)
    ap.add_argument('--coordinator-iterations', type=int, default=3)
    ap.add_argument('--component', action='store_true')
    ap.add_argument('--large-profile', action='store_true', help='candidate-only 1MiB profile workloads; old cases remain identical')
    ap.add_argument('--candidate-label', default='qualified-host', help='baseline/candidate evidence label; no timing selection changes')
    ap.add_argument('--frontend-schema', type=int, choices=(1, 2), default=2,
                    help='explicit qualified frontend package profile; use 1 for frozen baseline only')
    ap.add_argument('--isolated', action='store_true', help='coordinator asserts all build/gate reservations held')
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    require(args.isolated, 'requires explicit isolated timing admission; no gate may run alongside')
    require(args.iterations >= 5 and 1 <= args.edit_iterations < 100 and args.coordinator_iterations >= 1,
            'invalid/nonempty measurement selection')
    for name in ('compiler', 'component_dir', 'builder', 'source_root', 'zig'):
        setattr(args, name, getattr(args, name).resolve())
    args.modes = ['reference', 'shadow'] + (['component'] if args.component else [])
    manifests = packages(args.component_dir, args.frontend_schema)
    require(execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                    dict(os.environ), args.source_root, 600)[0] == 0, 'seed receipt verification failed')
    host = digest(args.compiler)
    with tempfile.TemporaryDirectory(prefix='frontend-measurement-') as temporary:
        work = Path(temporary)
        empty = work / 'empty-path'
        empty.mkdir()
        evidence = {'host_sha256': host, 'host_build_requirement': 'ReleaseFast, built before isolation',
                    'candidate_label': args.candidate_label, 'large_profile': args.large_profile,
                    'frontend_schema': args.frontend_schema,
                    'qualification_address_space_budget_bytes': ADDRESS_SPACE_BUDGET,
                    'native_cache_scope': 'private application cache starts empty; shared native units/runtime/toolchain may be warm across modes and hosts; inspect retained cache_evidence',
                    'fixed_mode_controls': {'MYLANG_TEST_INDEX_MODE': 'reference', 'MYLANG_CACHE_PLAN_MODE': 'reference'},
                    'measurement_scope': 'frontend-isolated workflows; auxiliary components held in reference mode, not production-default end-to-end timings',
                    'measurement_checks': 'fact/leak verification disabled; every sample validates observable status/output; separate correctness gate enables facts/leaks',
                    'affinity': sorted(os.sched_getaffinity(0)), 'packages': manifests,
                    'parser_transport': transport(args, work, empty),
                    'application': application(args, work, empty),
                    'coordinator': components(args, work)}
        evidence['children_peak_rss_kib'] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        evidence['rss_scope'] = 'cumulative child high-water for entire driver, including coordinator/compiler descendants; not per exchange'
    require(digest(args.compiler) == host and packages(args.component_dir, args.frontend_schema) == manifests,
            'measurement changed installed inputs')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'measurement': str(args.output), 'host_sha256': host,
                      'parser_transport_cases': len(evidence['parser_transport']),
                      'application_cases': len(evidence['application']), 'coordinator_cases': len(evidence['coordinator'])}))


if __name__ == '__main__':
    main()
