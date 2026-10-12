#!/usr/bin/env python3
"""Qualify all 23 additional core fixtures and the private-helper guest main.

Registered output oracles are read from C0. Benchmark rows use independent Python
checksums and a constant native clock, so these executions are not timings.
This harness owns bounded shared admission; never wrap it in build-slot.sh.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
import census

C0 = 'fbfcaa7a923186a8e773c3760f81c10aa345a432'
ORACLE_FILES = {}


def frozen(path):
    data = subprocess.check_output(['git', 'show', C0 + ':' + path], cwd=census.ROOT)
    ORACLE_FILES[path] = hashlib.sha256(data).hexdigest()
    return data.decode()


def constant(path, name):
    text = frozen(path)
    found = re.search(r'(?m)^\s*const ' + name + r' = (".*?");$', text)
    if found:
        return json.loads(found[1])
    found = re.search(r'(?m)^\s*const ' + name + r' =\n(.*?)^\s*;', text, re.S)
    assert found, (path, name)
    return '\n'.join(line.strip()[2:] for line in found[1].splitlines()
                     if line.strip().startswith('\\\\'))


def run(argv, stdout, status=0, diagnostics=()):
    return {'argv': argv, 'stdout': stdout, 'exit': status,
            'stderr_contains': list(diagnostics), 'cleanup_required': not diagnostics}


def score(text):
    data = text.encode('utf-8')
    return len(data) + sum(data)


def benchmark_checksum(name, size, iterations, seed):
    modulus = 1000000007
    if name == 'row_record_reads':
        return sum((seed + ((seed + step * (2 * seed + 1)) % size) * 17) % 1009
                   + (seed * 3 + ((seed + step * (2 * seed + 1)) % size) * 7) % 257
                   + ((seed + step * (2 * seed + 1)) % size) + seed
                   for step in range(iterations)) % modulus
    if name in ('row_mutate_shared', 'row_mutate_nested'):
        values = [(seed + j * 13 + (1 if name == 'row_mutate_nested' else 0)) % 1009
                  for j in range(size)]
        checksum = 0
        for step in range(iterations):
            index = (seed + step * 17) % size
            before = values[index]
            values[index] = (before + step + 1) % 1000003
            checksum += before + values[index]
        checksum += sum(values)
        if name == 'row_mutate_nested':
            checksum += sum((seed + j * 13 + k) % 1009
                            for j in range(size) for k in (0, 2, 3))
        return checksum % modulus
    if name == 'row_word_count':
        vocabulary = ['red', 'blue', 'café', 'red', 'green', 'blue', 'naïve', 'red']
        separators = [' ', '\t', '\n', '  ']
        document = ''.join(vocabulary[(seed + j) % 8] + separators[j % 4] for j in range(size))
        totals = [sum(score(word) * count * count for word, count in Counter((document + last).split()).items())
                  for last in ('red', 'blue')]
        return sum(totals[(seed + step) % 2] for step in range(iterations)) % modulus
    assert name == 'row_csv_aggregate'
    groups = [0, 0, 0]
    accepted = rejected = names = 0
    for j in range(size):
        if j % 11 == 0:
            rejected += 1
        elif (seed + j) % 3 != 0:
            groups[(seed + j) % 3] += (seed + j * 19) % 100003
            accepted += 1
            names += score(('café,"item"' if j % 2 == 0 else 'naïve,item') + str(j))
    return (groups[0] + 2 * groups[1] + 3 * groups[2] + accepted * 17 + rejected * 101 + names) * iterations % modulus


def contracts():
    values = 'src/core/value_e2e_test.zig'
    result = {name: [run([], constant(values, name + '_output'))]
              for name in ('v_mut', 'v_mut_window', 'v_nested', 'v_snapshot', 'v_wide_managed')}
    for name, path in (('ce2_results', 'src/core/ce2_results_test.zig'),
                       ('ce_records', 'src/core/ce_records_test.zig')):
        expected = constant(path, 'fixture_expected')
        result[name] = [run([], expected), run(['x'], expected, 1, ['error[R_OVERFLOW]'])]
    expected = ''.join(constant('src/core/ce2_effects_test.zig', name)
                       for name in ('fields_expected', 'takes_expected', 'stores_expected'))
    result['ce2_effects'] = [run([], expected),
                           run(['x'], expected, 1, ['error[R_LIST_BOUNDS]', '(index 7, length 1)']),
                           run(['y'], expected, 1, ['error[R_LIST_BOUNDS]', '(index 10, length 4)'])]
    common = constant('src/core/ce_lists_test.zig', 'expected_common')
    result['ce_elements'] = [run([], common), run(['x', 'y'], common + '99 z\n'),
                             run(['x', 'y', 'z', 'w'], common, 1,
                                 ['error[R_LIST_BOUNDS]', '(index 2, length 2)'])]
    result['ce_cow'] = [run([], '30115815 20000 1500 1000 1 4 0\n5 1009 5 9\n2 2 1 0\n')]
    result['f1_storeback'] = [run([], '7000070 600 457114\n-2513 -2993 -3000 8053\n'),
                              run(['x', 'y'], '25970094 1750 1399118\n-10353 -11753 -11760 14003\n')]
    result['rc_field_take'] = [run(['a', 'b'], '100000 100002 99999 199998 200005 100001 -1\n66667 66667 100000 3333266667 1 99999\n301 204 1 4 9\n')]
    result['rc_phi_fields'] = [run([], '48 1 1\n')]
    result['row_cow'] = [run([], frozen('test/core/row_cow.expected'))]
    result['u1_state'] = [run([], constant('src/core/u1_state_test.zig', 'state_expected'))]
    result['u1_sink'] = [run([], constant('src/core/u1_state_test.zig', 'sink_expected')),
                          run(['x'], '22017 1 6 17\n5797447\n20501002 1 120600\n', 1,
                              ['error[R_LIST_BOUNDS]', '(index 6, length 1)'])]
    result['rc_nonheld_captures'] = [run([], '')]
    for name in ('row_csv_aggregate', 'row_mutate_nested', 'row_mutate_shared', 'row_record_reads', 'row_word_count'):
        result[name] = [run([], '', 2), run(['1', '1', '1'], '', 2)]
        for params in ((8, 12, 7), (31, 37, 19)):
            result[name].append(run(list(map(str, params)), str(benchmark_checksum(name, *params)) + ' 0\n'))
    # Preserve provenance for inline constants as well as extracted constants.
    for path in ('src/core/ce_lists_test.zig', 'src/core/f1_facts_test.zig', 'src/core/own_test.zig'):
        frozen(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('compiler', 'zig', 'source-report', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--modes', nargs='+', choices=census.MODES, default=list(census.MODES))
    args = parser.parse_args()
    for key in ('compiler', 'zig', 'source_report', 'output'):
        setattr(args, key, getattr(args, key).resolve())
    source_report = json.loads(args.source_report.read_text())
    tree = Path(source_report['fixture_root'])
    assert census.digest(args.compiler) == source_report['compiler_sha256']
    cases = [row for row in source_report['cases'] if row['group'] == 'additional-23'
             or row['source'] == 'tests/lang/rc_nonheld_captures.my']
    assert len(cases) == 24 and all(row['status'] == 'admitted' for row in cases)
    expected = contracts()
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)
    report = {'schema': 'a03-common-core-contracts-v1', 'compiler_sha256': census.digest(args.compiler),
              'compiler_commit': source_report['fixture_commit'], 'source_root': str(tree),
              'harness_sha256': census.digest(__file__), 'census_helper_sha256': census.digest(census.__file__),
              'manifest': cases, 'oracles': expected, 'oracle_source_revision': C0,
              'oracle_source_hashes': ORACLE_FILES, 'modes': args.modes, 'cases': {}, 'failures': [],
              'benchmark_reference': 'Independent Python checksums from original input/kernel contracts; no C0 native execution or timing claim.',
              'trap_cleanup': 'Fatal traps retain reported managed live bytes; cleanup is not claimed at abort.'}
    (args.output / 'harness.py.snapshot').write_bytes(Path(__file__).read_bytes())
    clock = args.output / 'constant_clock.c'
    clock.write_text('#include <stdint.h>\nint64_t runtime_bench_now(void) { return 0; }\n')
    report['native_clock_sha256'] = census.digest(clock)
    lease = census.AdmissionLease(args.output, env, 50, 30)
    census.LEASE = lease
    audit = census.load_helper('a03_core_audit', 'experiments/zero-rc-20261011/audit.py')
    try:
        for mode in args.modes:
            for case in cases:
                source = tree / case['source']
                assert census.digest(source) == case['sha256']
                name = source.stem
                row = report['cases'].setdefault(case['source'], {'source_sha256': case['sha256'], 'modes': {}})
                directory = args.output / 'raw' / name / mode
                directory.mkdir(parents=True, exist_ok=True)
                flags = ['--experimental-zero-rc', *census.MODES[mode], '--zig', args.zig,
                         '--cache-dir', args.output / 'cache']
                public = re.findall(r'^public func (test_\w+)\(', source.read_text(), re.M)
                if public:
                    assert name in ('m_recursive_values', 'v_row_cow')
                    command = census.invoke([args.compiler, 'test', source, *flags, '--force', '--json',
                                             '--jobs', '1', '--seed', '7', '--property-runs', '12'],
                                            directory / 'test', env, admitted=True)
                    try:
                        parsed = json.loads(command['stdout'])
                    except ValueError:
                        parsed = {}
                    tests = parsed.get('tests', [])
                    passed = (command['exit'] == 0 and parsed.get('passed') == len(public)
                              and all(parsed.get(key) == 0 for key in ('failed', 'unsupported', 'skipped', 'cached'))
                              and {t['name'].split('::')[-1] for t in tests} == set(public)
                              and all(t.get('cache', {}).get('action') == 'execute' for t in tests))
                    lane = {'test_command': command, 'json_report': parsed, 'passed': passed,
                            'scope': 'Uninstrumented actual guest test command with leakcheck.'}
                else:
                    binary, llvm = directory / 'program', directory / 'program.ll'
                    build_command = [args.compiler, 'build', source, *flags, '--counters', '-o', binary, '--emit-llvm', llvm]
                    if name.startswith('row_') and name != 'row_cow':
                        build_command += ['--link', clock]
                    built = census.invoke(build_command, directory / 'build', env, admitted=True)
                    lane = {'build': built, 'passed': False, 'runs': []}
                    if built['exit'] == 0:
                        lane.update(binary_sha256=census.digest(binary), structural=census.structural(binary, llvm, directory, env))
                        for index, oracle in enumerate(expected[name]):
                            counts = directory / f'counts-{index}.json'
                            ran = census.invoke([binary, *oracle['argv']], directory / f'run-{index}', dict(env, MYLANG_COUNTERS=str(counts)))
                            diagnostics = oracle['stderr_contains']
                            ran['output_matches'] = (ran['exit'] == oracle['exit'] and ran['stdout'] == oracle['stdout']
                                                     and (all(t in ran['stderr'] for t in diagnostics) if diagnostics else not ran['stderr']))
                            ran['oracle'] = oracle
                            if counts.exists():
                                ran['audit'] = audit.audit(counts)
                                ran['totals'] = json.loads(counts.read_text())['totals']
                            ran['passed'] = (ran['output_matches'] and ran.get('audit', {}).get('observed_rc_free', False)
                                             and (not oracle['cleanup_required'] or ran.get('audit', {}).get('managed_leak_free', False)))
                            lane['runs'].append(ran)
                        lane['passed'] = lane['structural']['passed'] and all(ran['passed'] for ran in lane['runs'])
                row['modes'][mode] = lane
                if not lane['passed']:
                    report['failures'].append(case['source'] + '/' + mode)
                census.save(args.output / 'results.json', report)
                print(case['source'], mode, 'passed' if lane['passed'] else 'FAILED', flush=True)
    finally:
        lease.close()
        census.save(args.output / 'results.json', report)
    assert census.digest(args.compiler) == report['compiler_sha256']
    assert all(census.digest(tree / case['source']) == case['sha256'] for case in cases)
    return bool(report['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
