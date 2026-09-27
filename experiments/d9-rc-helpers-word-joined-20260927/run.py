#!/usr/bin/env python3
"""Four unchanged workloads on accepted GC, prior RC and joined RC.

This focused diagnostic cannot establish full 43-program acceptance. The
mandated harness supplies build commands, workloads and exact output checks.
"""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('measurement', ROOT / 'experiments/d9-rc-loops-joined-parity-20260927/run.py')
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)
A, PC = M.A, M.PC
SOURCE = 'c07016f308422b76cfe55607b26243efe0b4257e'
INTEGRATION = ROOT.parent / 'd9-rc-integration'
WORK = A.WORK / ('helpers-word-' + SOURCE[:8])
WORK.mkdir(exist_ok=True)
OUTPUT = WORK / 'results.json'
prior_path = A.WORK / 'joined-parity-49c6ca07/results.json'
baseline_path = A.WORK / 'gc-builds.json'
prior = json.loads(prior_path.read_text())
baseline = json.loads(baseline_path.read_text())
compilers = {
    'before': Path(prior['identity']['compiler']),
    'after': INTEGRATION / '.tmp-rc/install-helpers-word/bin/mylang',
}
assert baseline['compiler_sha256'] == A.GC_SHA == A.sha(baseline['compiler'])
assert baseline['inputs'] == prior['identity']['inputs'] == A.inputs()
assert A.sha(compilers['before']) == prior['identity']['compiler_sha256']
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=INTEGRATION, text=True).strip() == SOURCE
assert subprocess.run(['git', 'diff', '--quiet', 'HEAD'], cwd=INTEGRATION).returncode == 0
programs = [p for p in A.programs() if p['kind'] == 'schematic' or p['id'] == 'parity/micro/dict_count']
assert len(programs) == 4
identity = {
    'source_commit': SOURCE, 'before_source_commit': prior['identity']['compiler_commit'],
    'compilers': {side: {'path': str(path), 'sha256': A.sha(path)} for side, path in compilers.items()},
    'accepted_gc_compiler_sha256': A.GC_SHA,
    'baseline_manifest_sha256': A.sha(baseline_path), 'prior_receipt_sha256': A.sha(prior_path),
    'driver_sha256': A.sha(__file__), 'measurement_driver_sha256': A.sha(M.__file__),
    'inputs': A.inputs(), 'programs': programs, 'cpu': M.CPU,
}
state = {'identity': identity, 'diagnostic_only': True, 'builds': {}, 'samples': {}, 'counted': {}}
if OUTPUT.exists():
    state = json.loads(OUTPUT.read_text())
    assert state['identity'] == identity, 'changed diagnostic inputs'


def save():
    A.write(OUTPUT, state)


def manifest(binary, backend):
    path = Path(str(binary) + '.qbe-manifest.json')
    raw = path.read_text()
    data = json.loads(raw)
    assert data['backend'] == backend
    if backend == 'llvm':
        assert data['optimization'] == '3' and data['lto'] and not data['thin_lto']
    return {'path': str(path), 'sha256': A.sha(path), 'raw': raw, 'value': data}


jobs = {}
for program in programs:
    for backend in ('qbe', 'llvm'):
        key = program['build_key'] + '.' + backend
        for side, compiler in compilers.items():
            for stats in (False, True):
                if side == 'before' and not stats:
                    continue
                name = side + '.' + key + ('.stats' if stats else '')
                binary = WORK / 'bin' / name
                if name in state['builds']:
                    assert state['builds'][name]['ok'] and A.sha(binary) == state['builds'][name]['sha256']
                    continue
                command, cwd = PC.build_command(program, str(compiler), backend, binary, WORK / ('cache-' + side))
                command.append('--rc-runtime=stats' if stats else '--rc-runtime')
                jobs[name] = {'bin': binary, 'cmd': [str(ROOT / 'scripts/build-slot.sh'), 'build', *command], 'cwd': cwd}
save()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    pending = {pool.submit(PC.do_build, job): name for name, job in jobs.items()}
    for future in concurrent.futures.as_completed(pending):
        name = pending[future]
        result = future.result()
        state['builds'][name] = result
        save()
        assert result['ok'], result
        state['builds'][name]['manifest'] = manifest(jobs[name]['bin'], name.split('.')[2])
        save()
        print('built', name, flush=True)
assert len(state['builds']) == 12 and all(row['ok'] for row in state['builds'].values())

schematic = next(p for p in programs if p['kind'] == 'schematic')
command, cwd = PC.emit_command(schematic, str(compilers['after']))
emitted = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'],
                         cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
assert emitted.returncode == 0, emitted.stderr.decode(errors='replace')
state['schematic_emission'] = {'command': command, 'status': emitted.returncode,
                              'il_sha256': PC.sha(PC.il_text(emitted.stdout).encode()),
                              'declared': PC.declared_of(emitted.stdout)}
save()

for program in programs:
    for backend in ('qbe', 'llvm'):
        key = program['id'] + '|' + backend
        binary_key = program['build_key'] + '.' + backend
        binaries = {'gc': A.WORK / 'bin/gc' / binary_key,
                    'before': prior_path.parent / 'bin' / binary_key,
                    'after': WORK / 'bin' / ('after.' + binary_key)}
        assert A.sha(binaries['gc']) == baseline['builds'][binary_key]['sha256']
        assert A.sha(binaries['before']) == prior['builds'][binary_key]['sha256']
        declared = {'gc': baseline['schematic_declared'], 'before': prior['schematic_declared'],
                    'after': state['schematic_emission']['declared']}
        runs = {side: PC.run_spec(program, binary, 'helpers-word-' + side + '-' + backend, declared[side])
                for side, binary in binaries.items()}
        if key not in state['samples']:
            checks = {side: M.checked(program, run) for side, run in runs.items()}
            assert all(check['ok'] for check in checks.values()), checks
            observations = {side: {'perf': [], 'rss': []} for side in runs}
            for repetition in range(3):
                order = ('gc', 'before', 'after') if repetition % 2 == 0 else ('after', 'before', 'gc')
                for side in order:
                    perf, rss = M.counters(runs[side]), M.peak(runs[side])
                    assert perf['ok'] and rss['ok'], (perf, rss)
                    assert all(event['enabled_percent'] == 100 for event in perf['events'] if event['metric'] == 'instructions')
                    observations[side]['perf'].append(perf)
                    observations[side]['rss'].append(rss)
            medians = {side: {'instructions': statistics.median(v['instructions'] for v in rows['perf']),
                              'rss_kb': statistics.median(v['peak_rss_kb'] for v in rows['rss'])}
                       for side, rows in observations.items()}
            state['samples'][key] = {
                'checks': checks, 'runs': {side: M.receipt(run) for side, run in runs.items()},
                'binaries': {side: {'path': str(binary), 'sha256': A.sha(binary), 'manifest': manifest(binary, backend)}
                             for side, binary in binaries.items()},
                'observations': observations, 'medians': medians,
                'after_before': medians['after']['instructions'] / medians['before']['instructions'],
                'after_gc': medians['after']['instructions'] / medians['gc']['instructions'],
            }
            save()
            print(key, 'after/before', state['samples'][key]['after_before'], 'after/GC', state['samples'][key]['after_gc'], flush=True)
        for side in compilers:
            counted_key = key + '|' + side
            if counted_key in state['counted']:
                continue
            binary = WORK / 'bin' / (side + '.' + binary_key + '.stats')
            run = PC.run_spec(program, binary, 'helpers-word-counted-' + side + '-' + backend, declared[side])
            run['argv'] = ['taskset', '-c', str(M.CPU), *run['argv']]
            check = M.checked(program, run)
            assert check['ok'], check
            counters = [json.loads(line.split(' ', 1)[1]) for line in check['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
            assert len(counters) == 1, check
            n = counters[0]
            assert not n['saturated'] and n['hold_acquire'] == n['hold_release']
            assert n['heap_allocate'] == n['retire'] and n['owner_release'] == n['owner_acquire'] + n['heap_allocate']
            state['counted'][counted_key] = {'check': check, 'counts': n, 'run': M.receipt(run), 'binary_sha256': A.sha(binary)}
            save()

assert len(state['samples']) == 8 and len(state['counted']) == 16
assert A.inputs() == identity['inputs']
assert all(A.sha(path) == identity['compilers'][side]['sha256'] for side, path in compilers.items())
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=INTEGRATION, text=True).strip() == SOURCE
assert subprocess.run(['git', 'diff', '--quiet', 'HEAD'], cwd=INTEGRATION).returncode == 0
state['complete'] = True
save()
