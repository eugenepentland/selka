#!/usr/bin/env python3
"""Five unchanged target/control programs; instructions only, never full acceptance."""
import argparse
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location('measurement_core', HERE / 'measurement_core.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
M.CPU = 2
A, PC = M.A, M.PC
SELECTED = {'parity/micro/dict_count', 'lox/vm/binary_trees',
            'schematic/fixture', 'schematic/changed-net', 'schematic/changed-value'}


def counted(program, run):
    run = dict(run, argv=['taskset', '-c', str(M.CPU), *run['argv']])
    check = M.checked(program, run)
    rows = [line.removeprefix('MYLANG_RC_COUNTS ') for line in check.get('stderr', '').splitlines()
            if line.startswith('MYLANG_RC_COUNTS ')]
    counts = json.loads(rows[0]) if len(rows) == 1 else None
    balanced = counts is not None and not counts['saturated']
    if balanced:
        balanced = (counts['hold_acquire'] == counts['hold_release']
                    and counts['owner_release'] == counts['owner_acquire'] + counts['heap_allocate']
                    and counts['retire'] == counts['heap_allocate'] and counts['arena_allocate'] == 0
                    and counts['owner_limit'] == counts['hold_limit'] == 0)
    return {'run': M.receipt(run), 'check': check, 'counts': counts,
            'balanced': balanced, 'ok': check['ok'] and balanced}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--compiler-commit', required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    work = A.WORK / ('ownership-joined-' + args.compiler_commit[:8])
    work.mkdir(exist_ok=True)
    output = work / 'results.json'
    baseline_path = A.WORK / 'gc-builds.json'
    baseline = json.loads(baseline_path.read_text())
    assert baseline['compiler_sha256'] == A.GC_SHA == A.sha(baseline['compiler'])
    assert baseline['inputs'] == A.inputs()
    programs = [p for p in A.programs() if p['id'] in SELECTED]
    assert len(programs) == len(SELECTED)
    identity = {'compiler': str(compiler), 'compiler_sha256': A.sha(compiler),
                'compiler_commit': args.compiler_commit, 'compiler_mode': 'Debug',
                'inputs': A.inputs(), 'programs': programs, 'cpu': M.CPU,
                'driver_sha256': A.sha(__file__), 'measurement_core_sha256': A.sha(HERE / 'measurement_core.py'),
                'baseline_manifest_sha256': A.sha(baseline_path)}
    state = {'identity': identity, 'diagnostic_only': True, 'full_corpus_acceptance': False,
             'rss_measured': False, 'builds': {}, 'checks': {}, 'samples': {}, 'counted': {}}
    if output.exists():
        state = json.loads(output.read_text())
        assert state['identity'] == identity, 'cannot resume changed compiler, driver or inputs'
    jobs = {}
    for program in programs:
        for backend in ('qbe', 'llvm'):
            for stats in ((False,) if program['kind'] == 'schematic' else (False, True)):
                key = program['build_key'] + '.' + backend + ('.stats' if stats else '')
                binary = work / 'bin' / key
                if key in state['builds']:
                    assert state['builds'][key]['ok'] and A.sha(binary) == state['builds'][key]['sha256']
                    continue
                command, cwd = PC.build_command(program, str(compiler), backend, binary, work / 'cache')
                command.append('--rc-runtime=stats' if stats else '--rc-runtime')
                jobs[key] = {'bin': binary, 'cmd': [str(ROOT / 'scripts/build-slot.sh'), 'build', *command], 'cwd': cwd}
    A.write(output, state)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        pending = {pool.submit(PC.do_build, job): key for key, job in jobs.items()}
        for future in concurrent.futures.as_completed(pending):
            key = pending[future]
            state['builds'][key] = future.result()
            A.write(output, state)
            assert state['builds'][key]['ok'], state['builds'][key]
            print('built', key, flush=True)
    assert len(state['builds']) == 10
    schematic = next(p for p in programs if p['kind'] == 'schematic')
    command, cwd = PC.emit_command(schematic, str(compiler))
    emitted = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'],
                             cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
    assert emitted.returncode == 0, emitted.stderr.decode(errors='replace')
    declared = PC.declared_of(emitted.stdout)
    state['schematic_declared'] = declared
    state['schematic_il_sha256'] = PC.sha(PC.il_text(emitted.stdout).encode())
    for program in programs:
        for backend in ('qbe', 'llvm'):
            key = program['id'] + '|' + backend
            binary_key = program['build_key'] + '.' + backend
            assert A.sha(A.WORK / 'bin/gc' / binary_key) == baseline['builds'][binary_key]['sha256']
            if key not in state['samples']:
                runs = {'gc': PC.run_spec(program, A.WORK / 'bin/gc' / binary_key,
                                         'ownership-joined-gc-' + backend, baseline['schematic_declared']),
                        'rc': PC.run_spec(program, work / 'bin' / binary_key,
                                         'ownership-joined-rc-' + backend, declared)}
                checks = {side: M.checked(program, run) for side, run in runs.items()}
                state['checks'][key] = checks
                A.write(output, state)
                assert all(c['ok'] for c in checks.values()), checks
                observations = {side: [] for side in runs}
                for repetition in range(3):
                    for side in (('gc', 'rc') if repetition % 2 == 0 else ('rc', 'gc')):
                        start = time.monotonic()
                        receipt = M.counters(runs[side])
                        receipt['wrapper_wall_seconds'] = time.monotonic() - start
                        assert receipt['ok'], receipt
                        observations[side].append(receipt)
                medians = {side: {'instructions': statistics.median(r['instructions'] for r in rows),
                                  'wrapper_wall_seconds': statistics.median(r['wrapper_wall_seconds'] for r in rows)}
                           for side, rows in observations.items()}
                state['samples'][key] = {'checks': checks, 'runs': {side: M.receipt(run) for side, run in runs.items()},
                                         'observations': observations, 'medians': medians,
                                         'instruction_ratio': medians['rc']['instructions'] / medians['gc']['instructions']}
                A.write(output, state)
                print('measured', key, state['samples'][key]['instruction_ratio'], flush=True)
            if program['kind'] != 'schematic' and key not in state['counted']:
                run = PC.run_spec(program, work / 'bin' / (binary_key + '.stats'),
                                  'ownership-joined-counted-' + backend, declared)
                state['counted'][key] = counted(program, run)
                A.write(output, state)
                assert state['counted'][key]['ok'], state['counted'][key]
    assert A.inputs() == identity['inputs'] and A.sha(compiler) == identity['compiler_sha256']
    assert A.sha(baseline_path) == identity['baseline_manifest_sha256']
    assert A.sha(__file__) == identity['driver_sha256']
    assert A.sha(HERE / 'measurement_core.py') == identity['measurement_core_sha256']
    for key, build in state['builds'].items():
        assert A.sha(work / 'bin' / key) == build['sha256']
    state['complete_diagnostic'] = len(state['samples']) == 10 and len(state['counted']) == 4
    A.write(output, state)
    assert state['complete_diagnostic']
    print('complete diagnostic; no RSS or full-corpus acceptance claim', flush=True)


if __name__ == '__main__':
    main()
