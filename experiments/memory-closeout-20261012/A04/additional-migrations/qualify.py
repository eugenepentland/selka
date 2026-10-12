#!/usr/bin/env python3
"""Preserve the fourteen migrated fixtures' native outputs and intentional traps."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "experiments/memory-closeout-20261012/A04"))
import ownership_commands as ownership
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

spec = importlib.util.spec_from_file_location('library_qualification', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)

TRAPS = {
    't_methods': {
        'test_missing_index_traps_at_the_call': 'R_SUBSTRING_NOT_FOUND',
        'test_invalid_chr_traps_at_the_call': 'R_TEXT_SCALAR',
    },
    't_text': {
        'test_empty_separator_traps': 'R_EMPTY_SEPARATOR',
        'test_zero_slice_step_traps': 'R_SLICE_STEP',
    },
    't_scalar_fusion': {
        'test_empty_comparison_only_read_traps': 'R_TEXT_BOUNDS',
        'test_large_positive_index_traps': 'R_TEXT_BOUNDS (index 9223372036854775807, length 2)\n',
        'test_large_negative_index_traps': 'R_TEXT_BOUNDS (index -9223372036854775807, length 2)\n',
        'test_surrogate_construction_traps_before_scalar_uses': 'R_TEXT_SCALAR',
        'test_nonplace_unicode_index_reports_source_index_and_scalar_length': 'R_TEXT_BOUNDS (index 99, length 2)\n',
        'test_minimum_signed_index_reports_its_original_value': 'R_TEXT_BOUNDS (index -9223372036854775808, length 2)\n',
        'test_empty_separator_is_a_structured_native_trap': 'R_EMPTY_SEPARATOR',
        'test_out_of_range_byte_is_a_structured_native_trap': 'R_BYTE_RANGE',
        'test_missing_list_value_is_a_structured_native_trap': 'R_LIST_VALUE',
    },
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guest_tests(args, env, source, mode, flags, directory, expected_names):
    directory.mkdir(parents=True, exist_ok=True)
    command = [args.compiler, 'test', source, '--zig', args.zig, '--cache-dir', args.output / 'cache',
               *ownership.flags(args), *flags, '--force', '--json', '--jobs', '1']
    traps = TRAPS.get(source.stem, {})
    row = q.call(command, env, directory, 'test', expected=int(bool(traps)))
    assert row['stderr'] == '', row
    data = json.loads(row['stdout'])
    assert data['passed'] == len(expected_names) - len(traps) and data['failed'] == len(traps) and data['unsupported'] == 0, data
    actual_names = set()
    for test in data['tests']:
        name = test['name'].rsplit('::', 1)[-1]
        actual_names.add(name)
        if name in traps:
            assert test['status'] == 'failed' and test['reason'].startswith(traps[name]), test
        else:
            assert test['status'] == 'passed', test
        assert 'NativeTestProcessFailed' not in test['reason'], test
    assert actual_names == set(expected_names), (actual_names, expected_names)
    return {'status': 'passed', 'source_sha256': digest(source), 'public_tests': len(expected_names),
            'successful_tests': data['passed'], 'expected_traps': data['failed'], 'run': row,
            'counting': 'Guest-test commands verify leak checks and diagnostics; no RC counter claim from these commands.'}


def benchmark_row(args, env, source, mode, flags, directory):
    directory.mkdir(parents=True, exist_ok=True)
    llvm = directory / 'program.ll'
    binary = directory / 'program'
    build = q.call([args.compiler, 'build', source, '--zig', args.zig, '--cache-dir', args.output / 'cache',
                    *ownership.flags(args), *flags, '--counters', '--emit-llvm', llvm,
                    '--link', ROOT / 'benchmarks/runtime/ports/native_clock.c', '-o', binary], env, directory, 'build')
    q.prior.clean_ir(llvm)
    symbols = subprocess.check_output(['nm', str(binary)], text=True)
    assert not any(symbol in symbols for symbol in ('myl_core_retain', 'myl_core_release', 'myl_core_share'))
    # Fixed source-independent Python oracle, matching each frozen row's checksum.
    size, iterations, seed = 64, 9, 7
    options = ['', 'alpha', 'café', 'x', 'naïve']
    fragments = [options[(seed + j) % 5] for j in range(size)]
    score = lambda text: len(text.encode()) + sum(text.encode())
    if source.stem.endswith('join'):
        expected = sum(score(('|' if (seed + step) % 2 == 0 else '::').join(fragments)) for step in range(iterations))
    else:
        expected = iterations * (len(fragments) * 7 + sum(map(score, fragments)))
    counts = directory / 'counts.json'
    ran = q.call([binary, str(size), str(iterations), str(seed)], dict(env, MYLANG_COUNTERS=str(counts)), directory, 'run')
    assert ran['stderr'] == '', ran
    matched = re.fullmatch(r'(\d+) (\d+)\n', ran['stdout'])
    assert matched and int(matched[1]) == expected % 1000000007, ran
    audit = q.common.audit.audit(counts)
    assert audit['managed_leak_free'] and audit['observed_rc_free'], audit
    return {'status': 'passed', 'build': build, 'run': ran, 'audit': audit,
            'memory': q.common.census.summarize(json.loads(counts.read_text()))['whole_program'],
            'inputs': [size, iterations, seed], 'expected_checksum': expected,
            'source_sha256': digest(source), 'binary_sha256': digest(binary), 'llvm_sha256': digest(llvm),
            'timing': 'Printed elapsed time is ignored; this is correctness evidence, not a timing window.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ownership.add_option(parser)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--phase', required=True)
    parser.add_argument('--modes', nargs='+', choices=tuple(q.common.MODES), default=list(q.common.MODES))
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--cases', nargs='+', help='Explicit targeted subset; the fourteen-source assignment stays recorded.')
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.zig = args.zig.resolve()
    args.output = ROOT / '.tmp/memory-closeout/A04/additional-migrations' / args.phase
    evidence = HERE / args.phase
    report_file = evidence / 'results.json'
    originals = json.loads((HERE / 'originals.json').read_text())['sources']
    # Qualify the previously refused conditional/optional programs first, while
    # preserving all fourteen assigned sources in the completed denominator.
    originals.sort(key=lambda row: Path(row['source']).stem not in ('t_scalar_fusion', 'v_text'))
    oracles = json.loads((HERE / 'native-oracles.json').read_text())
    identity = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler), 'source_commit': args.source_commit,
                'sources': {row['source']: digest(ROOT / row['source']) for row in originals},
                'default_ownership': args.default_ownership, 'ownership_support_sha256': ownership.digest(), 'harness_sha256': digest(Path(__file__)), 'oracle_sha256': digest(HERE / 'native-oracles.json'), 'modes': args.modes, 'selected_cases': args.cases}
    if report_file.exists():
        assert args.resume, 'choose a new phase or --resume'
        report = json.loads(report_file.read_text())
        assert report['identity'] == identity, 'resume identity changed'
    else:
        assert not evidence.exists(), 'choose a new evidence phase'
        evidence.mkdir(parents=True)
        report = {'identity': identity, 'cases': {}, 'limitations': 'No performance claim; successful guest tests use leak checking; counted main programs include structural and RC audits.'}
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(name, None)
    selected = [row for row in originals if not args.cases or Path(row['source']).stem in args.cases]
    if args.cases:
        assert set(args.cases) == {Path(row['source']).stem for row in selected}, 'unknown targeted source'
    pending_sources = [row for row in selected if any(mode not in report['cases'].get(Path(row['source']).stem, {}) for mode in args.modes)]
    for first in range(0, len(pending_sources), 2):
        with admission('build'):
            for original in pending_sources[first:first + 2]:
                source = ROOT / original['source']
                rows = report['cases'].setdefault(source.stem, {})
                pending = [mode for mode in args.modes if mode not in rows]
                if source.stem.startswith('row_'):
                    provider = ROOT / 'benchmarks/runtime/ports/native_clock.c'
                    report['provider'] = {'source': str(provider.relative_to(ROOT)), 'source_sha256': digest(provider),
                                          'contract': '--link accepts C source; compiler owns compilation and depfile caching.'}
                for mode in pending:
                    flags = q.common.MODES[mode]
                    directory = args.output / source.stem / mode
                    try:
                        if original['public_tests']:
                            row = guest_tests(args, env, source, mode, flags, directory, original['public_tests'])
                        elif source.stem.startswith('row_'):
                            row = benchmark_row(args, env, source, mode, flags, directory)
                        else:
                            row = dict(ownership.lane(q, args, env, source.stem, source, [*ownership.flags(args), *flags], mode, 0,
                                              answer=oracles[source.stem]['stdout']), status='passed')
                    except (AssertionError, OSError, subprocess.SubprocessError) as error:
                        row = {'status': 'failed', 'error': str(error), 'source_sha256': digest(source)}
                    rows[mode] = row
                    target = evidence / 'raw' / source.stem / mode
                    target.mkdir(parents=True, exist_ok=True)
                    for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
                        for artifact in directory.glob(pattern):
                            shutil.copyfile(artifact, target / artifact.name)
                    report_file.write_text(json.dumps(report, indent=2) + '\n')
                    assert digest(args.compiler) == identity['compiler_sha256'], 'compiler changed'
                    print(source.stem, mode, row['status'], flush=True)
    report['summary'] = {'assigned_sources': len(originals), 'selected_sources': len(selected), 'expected_lanes': len(selected) * len(args.modes),
                         'completed_lanes': sum(map(len, report['cases'].values())),
                         'failed_lanes': sum(row['status'] != 'passed' for lanes in report['cases'].values() for row in lanes.values())}
    report_file.write_text(json.dumps(report, indent=2) + '\n')
    print(report['summary'], flush=True)
    return int(bool(report['summary']['failed_lanes']))


if __name__ == '__main__':
    raise SystemExit(main())
