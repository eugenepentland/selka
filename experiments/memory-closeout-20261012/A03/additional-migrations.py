#!/usr/bin/env python3
"""Qualify assigned core fixture mains, output/trap/trace contracts unchanged.

Owns bounded shared admission; do not wrap in build-slot.sh. Trap processes do
not unwind the managed heap, so their live bytes are recorded but not advertised
as a cleanup pass. Ordinary/Result exits still require zero exit-live bytes.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import sys

sys.dont_write_bytecode = True
import census

RUNS = {
    'counters': [([], '100 101 4\n', 0, []), (['x'], '100 101 4\n', 1, ['error[R_LIST_BOUNDS]'])],
    'f1_tbaa': [([], '6077 67108861 671088849\n902 30518 100056\n', 0, []),
                (['x', 'y'], '6234 234881021 968884428\n5055 31739 100084\n', 0, [])],
    'i_live_place': [([], '', 0, [])],
    'rc_alias_paths': [([], '62\n', 0, []), (['x'], '70\n', 0, [])],
    'v_inline_loops': [([], '', 0, [])],
    'v_narrow': [([], '2 105 140 3\n142 40 2\n0 -1\n', 0, [])],
    'v_trace': [([], 'run 3 8\nrun failed negative\n', 4, []),
                (['x'], 'run 4 8\nrun failed negative\n', 1,
                 ['error: negative\n', 'v_trace.my:9:16   parse    Err(...) created\n',
                  'v_trace.my:15:5   forward  returned\n', 'v_trace.my:19:13  pass_on  try propagated\n',
                  'v_trace.my:56:13  main     try propagated\n'])],
    'v_trap_set': [([], '9\n', 1, ['error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)'])],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--modes', nargs='+', choices=census.MODES, default=['release'])
    parser.add_argument('--files', nargs='+', choices=RUNS, default=list(RUNS))
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--ownership', choices=['opt-in', 'default'], default='opt-in')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, ZIG=str(args.zig.resolve()), MYLANG_ZIG=str(args.zig.resolve()), MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
        env.pop(key, None)
    lease = census.AdmissionLease(output, env, 10)
    census.LEASE = lease
    audit = census.load_helper('a03_additional_audit', 'experiments/zero-rc-20261011/audit.py')
    result = {'compiler_source_revision': args.source_revision, 'compiler_path': str(args.compiler.resolve()),
              'compiler_sha256': census.digest(args.compiler), 'harness_sha256': census.digest(__file__),
              'census_sha256': census.digest(census.__file__), 'ownership': args.ownership,
              'check_only': args.check_only, 'assigned_files': list(RUNS), 'selected_files': args.files,
              'modes': args.modes, 'planned_builds': len(args.files) * (1 if args.check_only else len(args.modes)),
              'files': {}, 'failures': []}
    (output / 'harness.py.snapshot').write_bytes(Path(__file__).read_bytes())
    (output / 'census.py.snapshot').write_bytes(Path(census.__file__).read_bytes())
    stop = False
    def checkpoint(_signal, _frame):
        nonlocal stop
        stop = True
    signal.signal(signal.SIGUSR1, checkpoint)
    try:
        for name in args.files:
            original = census.ROOT / 'test/core' / (name + '.my')
            source = output / 'sources' / original.name
            source.parent.mkdir(exist_ok=True)
            text = original.read_text()
            if name == 'v_inline_loops':
                text = text.replace('func main() -> int:\n    return 0', 'func main() -> int:\n    assert test_mut_loop_returns_and_shared_snapshots()\n    return 0')
            source.write_text(text)
            row = {'source_sha256': census.digest(original), 'executed_source_sha256': census.digest(source), 'modes': {}}
            result['files'][name] = row
            for mode in (['check'] if args.check_only else args.modes):
                directory = output / 'raw' / name / mode
                directory.mkdir(parents=True)
                binary, llvm = directory / 'program', directory / 'program.ll'
                command = [args.compiler.resolve(), 'check' if args.check_only else 'build', source,
                           '--cache-dir', output / 'cache']
                if args.ownership == 'opt-in':
                    command += ['--experimental-zero-rc']
                if not args.check_only:
                    command += ['--zig', args.zig.resolve(), *census.MODES[mode], '--counters', '-o', binary, '--emit-llvm', llvm]
                build = census.invoke(command, directory / 'build', env, admitted=True)
                item = {'build': build, 'runs': []}
                row['modes'][mode] = item
                if build['exit'] != 0:
                    result['failures'].append(name + '/' + mode + '/build')
                    if build['exit'] is None or build['exit'] < 0 or 'error[E_' not in build['stderr']:
                        stop = True
                        result['stop_reason'] = 'Compiler/tool failure without source diagnostic; do not repeat.'
                elif not args.check_only:
                    item.update(binary_sha256=census.digest(binary), structural=census.structural(binary, llvm, directory, env))
                    if not item['structural']['passed']:
                        result['failures'].append(name + '/' + mode + '/structural')
                    for index, (argv, expected, status, messages) in enumerate(RUNS[name]):
                        counts = directory / ('counts-' + str(index) + '.json')
                        ran = census.invoke([binary, *argv], directory / ('run-' + str(index)), dict(env, MYLANG_COUNTERS=str(counts)))
                        ran['expected'] = {'stdout': expected, 'exit': status, 'stderr_contains': messages}
                        ran['output_matches'] = ran['stdout'] == expected and ran['exit'] == status and (all(m in ran['stderr'] for m in messages) if messages else ran['stderr'] == '')
                        trap = any('R_LIST_BOUNDS' in m for m in messages)
                        if counts.exists():
                            ran['counts'] = json.loads(counts.read_text())
                            ran['audit'] = audit.audit(counts)
                        ran['cleanup_required'] = not trap
                        ran['passed'] = (ran['output_matches'] and ran.get('audit', {}).get('observed_rc_free', False)
                                         and (trap or ran.get('audit', {}).get('managed_leak_free', False)))
                        if not ran['passed']:
                            result['failures'].append(name + '/' + mode + '/run-' + str(index))
                        item['runs'].append(ran)
                census.save(output / 'results.json', result)
                print(name, mode, build['exit'], build['stderr'].split('\n')[0], flush=True)
                if stop:
                    result['checkpointed'] = True
                    return 3
    finally:
        lease.close()
        census.save(output / 'results.json', result)
    return bool(result['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
