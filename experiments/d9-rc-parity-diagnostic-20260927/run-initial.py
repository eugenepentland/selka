#!/usr/bin/env python3
"""Diagnostic parity/schematic slice of the unchanged D9 acceptance corpus.

This deliberately excludes Lox while its clone amplification is being fixed.
It never sets an acceptance verdict or overwrites either acceptance manifest.
"""
import argparse
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('acceptance', ROOT / 'experiments/d9-rc-acceptance-20260926/compare.py')
A = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(A)
PC = A.pc
CPU = 11


def peak(run):
    command = ['taskset', '-c', str(CPU), '/usr/bin/time', '-f', 'D9_RSS_KB=%M', *run['argv']]
    done = subprocess.run(command, cwd=run['cwd'], env=run['env'], capture_output=True, timeout=PC.RUN_TIMEOUT)
    rows = [line for line in done.stderr.decode(errors='replace').splitlines() if line.startswith('D9_RSS_KB=')]
    return {'command': command, 'status': done.returncode,
            'peak_rss_kb': int(rows[0].split('=', 1)[1]) if len(rows) == 1 else None,
            'stderr': done.stderr.decode(errors='replace')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--compiler-commit', required=True)
    args = parser.parse_args()
    compiler = Path(args.compiler).resolve()
    work = A.WORK / ('diagnostic-' + args.compiler_commit[:8])
    work.mkdir(exist_ok=True)
    output = work / 'results.json'
    baseline_path = A.WORK / 'gc-builds.json'
    baseline = json.loads(baseline_path.read_text())
    assert baseline['compiler_sha256'] == A.GC_SHA == A.sha(baseline['compiler'])
    assert baseline['inputs'] == A.inputs(), 'accepted corpus input changed'
    selected = [p for p in A.programs() if p['kind'] != 'lox']
    assert len(selected) == 30
    identity = {'compiler': str(compiler), 'compiler_sha256': A.sha(compiler),
                'compiler_commit': args.compiler_commit, 'baseline_manifest_sha256': A.sha(baseline_path),
                'driver_sha256': A.sha(__file__), 'inputs': A.inputs(), 'programs': selected, 'cpu': CPU}
    state = {'identity': identity, 'diagnostic_only': True, 'excluded': 'all 13 Lox VM cases per backend',
             'builds': {}, 'checks': {}, 'samples': {}, 'failures': []}
    if output.exists():
        state = json.loads(output.read_text())
        assert state['identity'] == identity
    jobs = {}
    for program in selected:
        for arm in ('qbe', 'llvm'):
            key = program['build_key'] + '.' + arm
            binary = work / 'bin' / key
            gc_binary = A.WORK / 'bin/gc' / key
            assert A.sha(gc_binary) == baseline['builds'][key]['sha256']
            if key in state['builds'] and state['builds'][key]['ok']:
                assert A.sha(binary) == state['builds'][key]['sha256']
                continue
            command, cwd = PC.build_command(program, str(compiler), arm, binary, work / 'cache')
            jobs[key] = {'bin': binary, 'cmd': [str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'], 'cwd': cwd}
    A.write(output, state)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        pending = {pool.submit(PC.do_build, job): key for key, job in jobs.items()}
        for future in concurrent.futures.as_completed(pending):
            key = pending[future]
            state['builds'][key] = future.result()
            A.write(output, state)
            print('build', key, state['builds'][key]['ok'], flush=True)
    assert len(state['builds']) == 56 and all(b['ok'] for b in state['builds'].values())
    schematic = next(p for p in selected if p['kind'] == 'schematic')
    command, cwd = PC.emit_command(schematic, str(compiler))
    emitted = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'],
                             cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
    assert emitted.returncode == 0, emitted.stderr.decode()
    declared = PC.declared_of(emitted.stdout)
    state['schematic_declared'] = declared
    state['schematic_il_sha256'] = PC.sha(PC.il_text(emitted.stdout).encode())
    for program in selected:
        for arm in ('qbe', 'llvm'):
            key = program['id'] + '|' + arm
            if key in state['samples']:
                continue
            binary_key = program['build_key'] + '.' + arm
            runs = {
                'gc': PC.run_spec(program, A.WORK / 'bin/gc' / binary_key, 'diag-gc-' + arm, baseline['schematic_declared']),
                'rc': PC.run_spec(program, work / 'bin' / binary_key, 'diag-rc-' + arm, declared),
            }
            checks = {side: PC.check(program, run) for side, run in runs.items()}
            state['checks'][key] = checks
            A.write(output, state)
            if not all(check['ok'] for check in checks.values()):
                state['failures'].append({'key': key, 'kind': 'output'})
                A.write(output, state)
                print('output failure', key, flush=True)
                continue
            observations = {side: {'perf': [], 'rss': []} for side in runs}
            for repeat in range(3):
                for side in (('gc', 'rc') if repeat % 2 == 0 else ('rc', 'gc')):
                    observations[side]['perf'].append(PC.perf_counts(runs[side], CPU))
                    observations[side]['rss'].append(peak(runs[side]))
            medians = {}
            for side, rows in observations.items():
                assert all(row['status'] == 0 and row.get('instructions', 0) > 0 for row in rows['perf']), (key, side, rows)
                assert all(row['status'] == 0 and row['peak_rss_kb'] is not None for row in rows['rss']), (key, side, rows)
                medians[side] = {'instructions': statistics.median(row['instructions'] for row in rows['perf']),
                                 'rss_kb': statistics.median(row['peak_rss_kb'] for row in rows['rss'])}
            ratio = medians['rc']['instructions'] / medians['gc']['instructions']
            state['samples'][key] = {'checks': checks, 'runs': runs, 'observations': observations,
                                     'medians': medians, 'instruction_ratio': ratio}
            A.write(output, state)
            print('measure', key, ratio, flush=True)
    assert identity['inputs'] == A.inputs() and identity['compiler_sha256'] == A.sha(compiler)
    state['complete_diagnostic'] = len(state['samples']) == 60 and not state['failures']
    A.write(output, state)
    assert state['complete_diagnostic']


if __name__ == '__main__':
    main()
