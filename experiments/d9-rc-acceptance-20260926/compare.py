#!/usr/bin/env python3
"""D9 WP-4: identical 43-program GC/RC corpus, median-three counters and RSS.

Prepare .tmp-rc-performance/lox from the accepted stage-3 corpus first. Build
one side with `build gc|rc --compiler PATH --compiler-commit HASH`; `measure`
requires both complete private manifests. GC is the accepted WP-4pre Debug
compiler. RC uses its explicit compiler flag, never an inherited environment.
All guest commands, workload sizes and checks come from the mandated pc.py.
"""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import statistics
import subprocess

TREE = Path(__file__).resolve().parents[2]
WORK = TREE / '.tmp-rc-performance'
GC_SHA = '8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478'
HARNESS = TREE / 'experiments/perf-gc-dict-20260925/scripts/pc.py'
os.environ['PC_WORK'] = str(WORK)
os.environ['TMPDIR'] = str(WORK / 'tmp')
os.environ['ZIG_LOCAL_CACHE_DIR'] = str(TREE / '.zig-cache-guests')
spec = importlib.util.spec_from_file_location('pc', HARNESS)
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    temporary = path.with_suffix('.pending.json')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def programs():
    historical = json.loads((TREE / 'experiments/perf-gc-dict-20260925/results.json').read_text())
    parity = {key.rsplit('|', 1)[0] for key in historical['samples'] if key.startswith('parity/')}
    selected = [p for p in pc.programs() if p['id'] in parity or p['id'].startswith(('schematic/', 'lox/vm/'))]
    assert len(parity) == 27 and len(selected) == 43
    assert sum(p['kind'] == 'schematic' for p in selected) == 3
    assert sum(p['kind'] == 'lox' for p in selected) == 13
    return selected


def inputs():
    paths = set()
    for root in (TREE / 'bench/parity', pc.SCHEMATIC_GUEST, pc.LOX_PORT):
        paths.update(root.rglob('*.my'))
        paths.update(root.rglob('mylang.json'))
    for root in (pc.LOX_BENCH, pc.SCHEMATIC_PROJECTS):
        paths.update(p for p in root.rglob('*') if p.is_file())
    paths.update(Path(p['expected_path']) for p in programs() if 'expected_path' in p)
    paths.update((pc.SCHEMATIC_PROVIDER, HARNESS, Path(__file__).resolve()))
    return {str(p): sha(p) for p in sorted(paths)}


def build(opts):
    compiler = Path(opts.compiler).resolve()
    identity = sha(compiler)
    if opts.side == 'gc':
        assert identity == GC_SHA, 'GC must be the accepted WP-4pre compiler'
    manifest = WORK / (opts.side + '-builds.json')
    state = {
        'compiler': str(compiler), 'compiler_sha256': identity,
        'compiler_commit': opts.compiler_commit, 'compiler_mode': 'Debug',
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=TREE, text=True).strip(),
        'runtime': opts.side, 'inputs': inputs(), 'programs': programs(),
        'builds': {}, 'checks': {},
    }
    if manifest.exists():
        previous = json.loads(manifest.read_text())
        for key in ('compiler_sha256', 'compiler_commit', 'runtime', 'inputs', 'programs'):
            assert previous[key] == state[key], ('cannot resume changed inputs', key)
        state = previous
    jobs = {}
    for program in programs():
        for arm in ('qbe', 'llvm'):
            key = program['build_key'] + '.' + arm
            if key in jobs:
                continue
            binary = WORK / 'bin' / opts.side / key
            prior = state['builds'].get(key)
            if prior and prior['ok']:
                assert sha(binary) == prior['sha256'], ('private artifact changed', key)
                continue
            command, cwd = pc.build_command(program, str(compiler), arm, binary, WORK / ('cache-' + opts.side))
            if opts.side == 'rc':
                command.append('--rc-runtime')
            jobs[key] = {'bin': binary, 'cmd': [str(TREE / 'scripts/build-slot.sh'), 'build', *command], 'cwd': cwd}
    write(manifest, state)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        pending = {pool.submit(pc.do_build, job): key for key, job in jobs.items()}
        for future in concurrent.futures.as_completed(pending):
            key = pending[future]
            outcome = future.result()
            state['builds'][key] = outcome
            write(manifest, state)
            print(opts.side, key, 'PASS' if outcome['ok'] else 'FAIL', flush=True)
            if not outcome['ok']:
                print(outcome['stderr'], flush=True)
    assert len(state['builds']) == 58 and all(b['ok'] for b in state['builds'].values())
    schematic = next(p for p in programs() if p['kind'] == 'schematic')
    command, cwd = pc.emit_command(schematic, str(compiler))
    if opts.side == 'rc':
        command.append('--rc-runtime')
    emitted = subprocess.run(command, cwd=cwd, env=pc.clean_env(), capture_output=True, timeout=1200)
    assert emitted.returncode == 0, emitted.stderr.decode()
    state['schematic_declared'] = pc.declared_of(emitted.stdout)
    state['schematic_il_sha256'] = hashlib.sha256(pc.il_text(emitted.stdout).encode()).hexdigest()
    for program in programs():
        for arm in ('qbe', 'llvm'):
            key = program['id'] + '|' + arm
            binary = WORK / 'bin' / opts.side / (program['build_key'] + '.' + arm)
            run = pc.run_spec(program, binary, opts.side + '-' + arm, state['schematic_declared'])
            state['checks'][key] = pc.check(program, run)
            write(manifest, state)
            print('check', opts.side, key, state['checks'][key]['ok'], flush=True)
    assert all(c['ok'] for c in state['checks'].values())
    assert inputs() == state['inputs'] and sha(compiler) == identity


def rss(run):
    command = ['taskset', '-c', '2', '/usr/bin/time', '-f', 'D9_RSS_KB=%M', *run['argv']]
    done = subprocess.run(command, cwd=run['cwd'], env=run['env'], stdout=subprocess.DEVNULL,
                          stderr=subprocess.PIPE, text=True, timeout=pc.RUN_TIMEOUT)
    assert done.returncode == 0, (command, done.returncode, done.stderr)
    rows = [line for line in done.stderr.splitlines() if line.startswith('D9_RSS_KB=')]
    assert len(rows) == 1
    return {'status': done.returncode, 'peak_rss_kb': int(rows[0].split('=', 1)[1])}


def measure():
    states = {side: json.loads((WORK / (side + '-builds.json')).read_text()) for side in ('gc', 'rc')}
    assert states['gc']['compiler_sha256'] == GC_SHA
    assert states['gc']['inputs'] == states['rc']['inputs'] == inputs()
    assert states['gc']['programs'] == states['rc']['programs'] == programs()
    for side, state in states.items():
        assert len(state['checks']) == 86 and all(c['ok'] for c in state['checks'].values())
        for key, built in state['builds'].items():
            assert built['ok'] and sha(WORK / 'bin' / side / key) == built['sha256']
    result = {'states': states, 'cpu': 2, 'perf_reps': 3, 'rss_reps': 3, 'samples': {}}
    output = WORK / 'comparison.json'
    if output.exists():
        previous = json.loads(output.read_text())
        assert previous['states'] == states
        result = previous
    for program in programs():
        for arm in ('qbe', 'llvm'):
            key = program['id'] + '|' + arm
            if key in result['samples']:
                continue
            runs = {side: pc.run_spec(program, WORK / 'bin' / side / (program['build_key'] + '.' + arm),
                                     side + '-' + arm, state['schematic_declared']) for side, state in states.items()}
            checks = {side: pc.check(program, run) for side, run in runs.items()}
            assert all(check['ok'] for check in checks.values()), (key, checks)
            observations = {side: {'perf': [], 'rss': []} for side in states}
            for repetition in range(3):
                for side in (('gc', 'rc') if repetition % 2 == 0 else ('rc', 'gc')):
                    counted = pc.perf_counts(runs[side], 2)
                    assert counted['status'] == 0 and counted.get('instructions', 0) > 0, (key, side, counted)
                    observations[side]['perf'].append(counted)
                    observations[side]['rss'].append(rss(runs[side]))
            medians = {side: {'instructions': statistics.median(p['instructions'] for p in data['perf']),
                              'rss_kb': statistics.median(p['peak_rss_kb'] for p in data['rss'])}
                       for side, data in observations.items()}
            ratio = medians['rc']['instructions'] / medians['gc']['instructions']
            result['samples'][key] = {'checks': checks, 'observations': observations, 'medians': medians,
                                      'instruction_ratio': ratio}
            write(output, result)
            print(key, ratio, medians, flush=True)
    arms = {}
    for arm in ('qbe', 'llvm'):
        rows = {key: row for key, row in result['samples'].items() if key.endswith('|' + arm)}
        geomean = statistics.geometric_mean(row['instruction_ratio'] for row in rows.values())
        outliers = {key: row['instruction_ratio'] for key, row in rows.items() if row['instruction_ratio'] > 1.3}
        med_rss = {side: statistics.median(row['medians'][side]['rss_kb'] for row in rows.values()) for side in states}
        passed = len(rows) == 43 and geomean <= 1.0 and not outliers and med_rss['rc'] < med_rss['gc']
        arms[arm] = {'count': len(rows), 'instruction_geomean': geomean, 'outliers': outliers,
                     'median_program_rss_kb': med_rss, 'passed': passed}
    result['acceptance'] = {'arms': arms, 'passed': len(result['samples']) == 86 and all(a['passed'] for a in arms.values())}
    write(output, result)
    print(json.dumps(result['acceptance'], indent=2), flush=True)
    assert result['acceptance']['passed'], 'WP-4 performance acceptance not met'


if __name__ == '__main__':
    WORK.mkdir(exist_ok=True)
    (WORK / 'tmp').mkdir(exist_ok=True)
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    builder = actions.add_parser('build')
    builder.add_argument('side', choices=('gc', 'rc'))
    builder.add_argument('--compiler', required=True)
    builder.add_argument('--compiler-commit', required=True)
    actions.add_parser('measure')
    options = parser.parse_args()
    build(options) if options.action == 'build' else measure()
