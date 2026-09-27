#!/usr/bin/env python3
"""Immutable 30-program parity/schematic diagnostic, with raw perf evidence.

This reuses the mandated corpus, commands, exact output checks and workload sizes.
All 13 Lox VM workloads are excluded from this diagnostic. No result here
can establish complete Stage 4 performance acceptance.
"""
import argparse
import concurrent.futures
import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('acceptance', ROOT / 'experiments/d9-rc-acceptance-20260926/compare.py')
A = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(A)
PC = A.pc
CPU = 2


def receipt(run):
    return {key: ({name: value for name, value in data.items() if name.startswith('MYLANG_')}
                  if key == 'env' else str(data) if isinstance(data, Path) else data)
            for key, data in run.items()}


def execute(command, run):
    process = subprocess.Popen(command, cwd=run['cwd'], env=run['env'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
    try:
        _, stderr = process.communicate(timeout=PC.RUN_TIMEOUT)
        return {'command': command, 'status': process.returncode, 'stderr': stderr.decode(errors='replace')}
    except subprocess.TimeoutExpired:
        # This session contains only this measurement wrapper and its guest.
        os.killpg(process.pid, signal.SIGKILL)
        _, stderr = process.communicate()
        return {'command': command, 'status': 'timeout', 'timeout_seconds': PC.RUN_TIMEOUT,
                'stderr': stderr.decode(errors='replace')}


def counters(run):
    result = execute(['taskset', '-c', str(CPU), 'perf', 'stat', '--no-big-num', '-x,',
                      '-e', 'instructions:u,cycles:u', '--', *run['argv']], run)
    events = []
    for line in result['stderr'].splitlines():
        fields = line.split(',')
        if len(fields) < 5 or 'cpu_atom' in fields[2]:
            continue
        metric = 'instructions' if 'instructions' in fields[2] else 'cycles' if 'cycles' in fields[2] else None
        if metric is None or not fields[0].strip().isdigit():
            continue
        try:
            event = {'metric': metric, 'event': fields[2], 'count': int(fields[0]),
                     'enabled_percent': float(fields[4]), 'run_time': fields[3]}
        except ValueError:
            continue
        events.append(event)
    result['events'] = events
    instructions = [event for event in events if event['metric'] == 'instructions']
    result['ok'] = (result['status'] == 0 and len(instructions) == 1
                    and instructions[0]['count'] > 0 and instructions[0]['enabled_percent'] >= 99.9)
    if result['ok']:
        result['instructions'] = instructions[0]['count']
    return result


def peak(run):
    result = execute(['taskset', '-c', str(CPU), '/usr/bin/time', '-f', 'D9_RSS_KB=%M', *run['argv']], run)
    values = [line.split('=', 1)[1] for line in result['stderr'].splitlines() if line.startswith('D9_RSS_KB=')]
    result['ok'] = result['status'] == 0 and len(values) == 1 and values[0].isdigit() and int(values[0]) > 0
    if result['ok']:
        result['peak_rss_kb'] = int(values[0])
    return result


def checked(program, run):
    try:
        return PC.check(program, run)
    except subprocess.TimeoutExpired:
        return {'ok': False, 'status': 'timeout', 'timeout_seconds': PC.RUN_TIMEOUT}


def summarize(samples):
    result = {}
    for backend in ('qbe', 'llvm'):
        rows = [row for key, row in samples.items() if key.endswith('|' + backend)]
        if len(rows) != 30:
            result[backend] = {'complete_diagnostic': False, 'programs': len(rows), 'subset_thresholds_pass': False}
            continue
        geometric = math.exp(statistics.mean(math.log(row['instruction_ratio']) for row in rows))
        memory = {side: statistics.median(row['medians'][side]['rss_kb'] for row in rows) for side in ('gc', 'rc')}
        maximum = max(row['instruction_ratio'] for row in rows)
        result[backend] = {'complete_diagnostic': True, 'programs': 30, 'instruction_geomean': geometric,
                           'maximum_instruction_ratio': maximum, 'median_peak_rss_kb': memory,
                           'subset_thresholds_pass': geometric <= 1.0 and maximum <= 1.3 and memory['rc'] < memory['gc']}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--compiler-commit', required=True)
    args = parser.parse_args()
    compiler = Path(args.compiler).resolve()
    work = A.WORK / ('joined-parity-' + args.compiler_commit[:8])
    work.mkdir(exist_ok=True)
    output = work / 'results.json'
    baseline_path = A.WORK / 'gc-builds.json'
    baseline = json.loads(baseline_path.read_text())
    assert baseline['compiler_sha256'] == A.GC_SHA == A.sha(baseline['compiler'])
    assert baseline['inputs'] == A.inputs()
    selected = [program for program in A.programs() if program['kind'] != 'lox']
    assert len(selected) == 30
    identity = {'compiler': str(compiler), 'compiler_sha256': A.sha(compiler),
                'compiler_commit': args.compiler_commit, 'baseline_manifest_sha256': A.sha(baseline_path),
                'driver_sha256': A.sha(__file__), 'inputs': A.inputs(), 'programs': selected, 'cpu': CPU}
    state = {'identity': identity, 'diagnostic_only': True, 'excluded': 'all 13 Lox VM programs per backend', 'builds': {}, 'checks': {}, 'samples': {}, 'failures': [],
             'environment_recording': 'Only explicit MYLANG_* overrides retained; unrelated inherited host environment omitted.'}
    if output.exists():
        state = json.loads(output.read_text())
        assert state['identity'] == identity, 'cannot resume changed compiler, driver or corpus'
    jobs = {}
    for program in selected:
        for backend in ('qbe', 'llvm'):
            key = program['build_key'] + '.' + backend
            binary = work / 'bin' / key
            assert A.sha(A.WORK / 'bin/gc' / key) == baseline['builds'][key]['sha256']
            if key in state['builds'] and state['builds'][key]['ok']:
                assert A.sha(binary) == state['builds'][key]['sha256']
                continue
            command, cwd = PC.build_command(program, str(compiler), backend, binary, work / 'cache')
            jobs[key] = {'bin': binary, 'cmd': [str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'], 'cwd': cwd}
    A.write(output, state)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        pending = {pool.submit(PC.do_build, job): key for key, job in jobs.items()}
        for future in concurrent.futures.as_completed(pending):
            key = pending[future]
            state['builds'][key] = future.result()
            A.write(output, state)
            print('build', key, state['builds'][key]['ok'], flush=True)
    assert len(state['builds']) == 56 and all(row['ok'] for row in state['builds'].values())
    schematic = next(program for program in selected if program['kind'] == 'schematic')
    command, cwd = PC.emit_command(schematic, str(compiler))
    emitted = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'],
                             cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
    assert emitted.returncode == 0, emitted.stderr.decode(errors='replace')
    declared = PC.declared_of(emitted.stdout)
    state['schematic_declared'] = declared
    state['schematic_il_sha256'] = PC.sha(PC.il_text(emitted.stdout).encode())
    for program in selected:
        for backend in ('qbe', 'llvm'):
            key = program['id'] + '|' + backend
            if key in state['samples'] or any(failure['key'] == key for failure in state['failures']):
                continue
            binary_key = program['build_key'] + '.' + backend
            runs = {'gc': PC.run_spec(program, A.WORK / 'bin/gc' / binary_key, 'corpus-gc-' + backend, baseline['schematic_declared']),
                    'rc': PC.run_spec(program, work / 'bin' / binary_key, 'corpus-rc-' + backend, declared)}
            checks = {side: checked(program, run) for side, run in runs.items()}
            state['checks'][key] = checks
            A.write(output, state)
            if not all(check['ok'] for check in checks.values()):
                state['failures'].append({'key': key, 'kind': 'output', 'checks': checks})
                A.write(output, state)
                print('output failure', key, flush=True)
                continue
            observations = {side: {'perf': [], 'rss': []} for side in runs}
            failed = False
            for repetition in range(3):
                for side in (('gc', 'rc') if repetition % 2 == 0 else ('rc', 'gc')):
                    observations[side]['perf'].append(counters(runs[side]))
                    observations[side]['rss'].append(peak(runs[side]))
                    if not observations[side]['perf'][-1]['ok'] or not observations[side]['rss'][-1]['ok']:
                        failed = True
                        break
                if failed:
                    break
            if failed:
                state['failures'].append({'key': key, 'kind': 'measurement', 'observations': observations})
                A.write(output, state)
                print('measurement failure', key, flush=True)
                continue
            medians = {side: {'instructions': statistics.median(row['instructions'] for row in values['perf']),
                               'rss_kb': statistics.median(row['peak_rss_kb'] for row in values['rss'])}
                       for side, values in observations.items()}
            ratio = medians['rc']['instructions'] / medians['gc']['instructions']
            state['samples'][key] = {'checks': checks, 'runs': {side: receipt(run) for side, run in runs.items()},
                                     'observations': observations, 'medians': medians, 'instruction_ratio': ratio}
            A.write(output, state)
            print('measure', key, ratio, flush=True)
    assert identity['inputs'] == A.inputs() and identity['compiler_sha256'] == A.sha(compiler)
    assert A.sha(baseline_path) == identity['baseline_manifest_sha256']
    for key, built in state['builds'].items():
        assert A.sha(work / 'bin' / key) == built['sha256']
        assert A.sha(A.WORK / 'bin/gc' / key) == baseline['builds'][key]['sha256']
    state['summary'] = summarize(state['samples'])
    state['complete_diagnostic'] = len(state['samples']) == 60 and not state['failures']
    state['subset_thresholds_pass'] = state['complete_diagnostic'] and all(row['subset_thresholds_pass'] for row in state['summary'].values())
    A.write(output, state)
    print('complete_diagnostic', state['complete_diagnostic'], 'subset_thresholds_pass', state['subset_thresholds_pass'], flush=True)
    raise SystemExit(0 if state['complete_diagnostic'] else 1)


if __name__ == '__main__':
    main()
