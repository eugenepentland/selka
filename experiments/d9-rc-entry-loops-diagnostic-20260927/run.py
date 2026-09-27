#!/usr/bin/env python3
"""Unchanged 30 non-Lox programs plus full Lox binary_trees N10: diagnostic only.

Separate build/measure phases let the immutable compiler identity be reviewed
before timing. Reuses the mandated harness and preserves all earlier receipts.
"""
import argparse
import concurrent.futures
import importlib.util
import json
import math
import os
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('measure', ROOT / 'experiments/d9-rc-loops-joined-parity-20260927/run.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
A, PC = M.A, M.PC
M.CPU = 11
SOURCE = '4e5c0cd638e55b86ef0d99112872e02ae41dbe89'
INTEGRATION = ROOT.parent / 'd9-rc-integration'
COMPILER = INTEGRATION / '.tmp-rc/install-entry-loops/bin/mylang'
READY = INTEGRATION / '.tmp-rc/entry-loops-build-ready'
HASH = INTEGRATION / '.tmp-rc/entry-loops-compiler.sha256'
WORK = A.WORK / ('entry-loops-' + SOURCE[:8])
WORK.mkdir(exist_ok=True)
(WORK / 'tmp').mkdir(exist_ok=True)
os.environ['TMPDIR'] = str(WORK / 'tmp')
os.environ['ZIG_LOCAL_CACHE_DIR'] = str(WORK / 'zig-cache')
OUTPUT = WORK / 'results.json'
BASELINE = A.WORK / 'gc-builds.json'
PRIOR = A.WORK / 'joined-parity-49c6ca07/results.json'


def native_manifest(binary, backend):
    path = Path(str(binary) + '.qbe-manifest.json')
    data = json.loads(path.read_text())
    assert data['backend'] == backend
    if backend == 'llvm':
        assert data['optimization'] == '3' and data['lto'] and not data['thin_lto']
    return {'path': str(path), 'sha256': A.sha(path), 'value': data}


def summary(samples, nonlox=False):
    answer = {}
    for backend in ('qbe', 'llvm'):
        rows = [r for k, r in samples.items() if k.endswith('|' + backend) and (not nonlox or not k.startswith('lox/'))]
        expected = 30 if nonlox else 31
        answer[backend] = {'programs': len(rows), 'complete': len(rows) == expected}
        if rows:
            answer[backend].update(instruction_geomean=math.exp(statistics.mean(math.log(r['instruction_ratio']) for r in rows)),
                                   maximum_instruction_ratio=max(r['instruction_ratio'] for r in rows),
                                   rows_within_1_3=sum(r['instruction_ratio'] <= 1.3 for r in rows),
                                   median_peak_rss_kb={side: statistics.median(r['medians'][side]['rss_kb'] for r in rows) for side in ('gc', 'rc')})
    return answer


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('phase', choices=['build', 'measure'])
    phase = args.parse_args().phase
    assert READY.exists(), 'root compiler install is not ready'
    compiler_sha = A.sha(COMPILER)
    assert HASH.read_text().split()[0] == compiler_sha
    baseline = json.loads(BASELINE.read_text())
    prior = json.loads(PRIOR.read_text())
    assert baseline['compiler_sha256'] == A.GC_SHA == A.sha(baseline['compiler'])
    assert baseline['inputs'] == prior['identity']['inputs'] == A.inputs()
    programs = [p for p in A.programs() if p['kind'] != 'lox']
    programs += [p for p in A.programs() if p['id'] == 'lox/vm/binary_trees']
    assert len(programs) == 31 and programs[-1]['size'] == 10
    identity = {'compiler': str(COMPILER), 'compiler_sha256': compiler_sha, 'compiler_commit': SOURCE,
                'driver_sha256': A.sha(__file__), 'measurement_driver_sha256': A.sha(M.__file__),
                'baseline_manifest_sha256': A.sha(BASELINE), 'prior_receipt_sha256': A.sha(PRIOR),
                'accepted_gc_compiler_sha256': A.GC_SHA, 'inputs': A.inputs(), 'programs': programs,
                'cpu': M.CPU, 'compiler_mode': 'Debug', 'source_merge': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
    state = {'identity': identity, 'diagnostic_only': True, 'excluded': 'remaining 12 Lox programs; not 43-program acceptance',
             'builds': {}, 'checks': {}, 'samples': {}, 'counted': {}, 'failures': []}
    if OUTPUT.exists():
        state = json.loads(OUTPUT.read_text())
        assert state['identity'] == identity, 'resume requires unchanged compiler, source, driver and inputs'
    def save(): A.write(OUTPUT, state)
    def identities():
        assert READY.exists() and A.sha(COMPILER) == compiler_sha == HASH.read_text().split()[0]
        assert A.inputs() == identity['inputs'] and A.sha(BASELINE) == identity['baseline_manifest_sha256']
        assert A.sha(PRIOR) == identity['prior_receipt_sha256']
    jobs = {}
    for p in programs:
        for backend in ('qbe', 'llvm'):
            basekey = p['build_key'] + '.' + backend
            assert A.sha(A.WORK / 'bin/gc' / basekey) == baseline['builds'][basekey]['sha256']
            for stats in (False, True):
                key = basekey + ('.stats' if stats else '')
                binary = WORK / 'bin' / key
                if key in state['builds'] and state['builds'][key]['ok']:
                    assert A.sha(binary) == state['builds'][key]['sha256']
                    continue
                command, cwd = PC.build_command(p, str(COMPILER), backend, binary, WORK / 'cache')
                command.append('--rc-runtime=stats' if stats else '--rc-runtime')
                jobs[key] = {'bin': binary, 'cmd': [str(ROOT / 'scripts/build-slot.sh'), 'build', *command], 'cwd': cwd}
    if phase == 'build':
        save()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            pending = {pool.submit(PC.do_build, job): key for key, job in jobs.items()}
            for future in concurrent.futures.as_completed(pending):
                key = pending[future]
                row = future.result()
                if row['ok']:
                    row['manifest'] = native_manifest(jobs[key]['bin'], key.split('.')[1])
                state['builds'][key] = row
                save()
                print('build', key, row['ok'], flush=True)
        assert len(state['builds']) == 116 and all(x['ok'] for x in state['builds'].values())
        schematic = next(p for p in programs if p['kind'] == 'schematic')
        command, cwd = PC.emit_command(schematic, str(COMPILER))
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime']
        emitted = subprocess.run(command, cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
        assert emitted.returncode == 0, emitted.stderr.decode(errors='replace')
        state['schematic_declared'] = PC.declared_of(emitted.stdout)
        state['schematic_emission'] = {'command':command,'status':0,'stderr':emitted.stderr.decode(errors='replace'),'il_sha256':PC.sha(PC.il_text(emitted.stdout).encode())}
        state['prepared'] = True
        identities();save();print('prepared116 builds; no timed executions yet',flush=True)
        return
    assert not jobs and state.get('prepared'), 'complete build phase first'
    for p in programs:
        for backend in ('qbe', 'llvm'):
            key = p['id'] + '|' + backend
            binarykey = p['build_key'] + '.' + backend
            binaries = {'gc':A.WORK / 'bin/gc' / binarykey,'rc':WORK / 'bin' / binarykey}
            declared = {'gc':baseline['schematic_declared'],'rc':state['schematic_declared']}
            runs = {side:PC.run_spec(p,binary,'entry-loops-'+side+'-'+backend,declared[side]) for side,binary in binaries.items()}
            if key not in state['samples']:
                checks = {side:M.checked(p,run) for side,run in runs.items()}
                state['checks'][key] = checks;save()
                assert all(x['ok'] for x in checks.values()), checks
                observations = {side:{'perf':[],'rss':[]} for side in runs}
                for repetition in range(3):
                    for side in (('gc','rc') if repetition % 2 == 0 else ('rc','gc')):
                        perf = M.counters(runs[side]);observations[side]['perf'].append(perf)
                        state['inflight'] = {'key':key,'observations':observations};save()
                        assert perf['ok'] and all(e['enabled_percent']==100.0 for e in perf['events'] if e['metric']=='instructions'), perf
                        rss = M.peak(runs[side]);observations[side]['rss'].append(rss)
                        state['inflight'] = {'key':key,'observations':observations};save()
                        assert rss['ok'],rss
                medians = {side:{'instructions':statistics.median(x['instructions'] for x in rows['perf']),
                                 'rss_kb':statistics.median(x['peak_rss_kb'] for x in rows['rss'])} for side,rows in observations.items()}
                ratio = medians['rc']['instructions']/medians['gc']['instructions']
                row = {'checks':checks,'runs':{side:M.receipt(run) for side,run in runs.items()},'observations':observations,
                       'medians':medians,'instruction_ratio':ratio,'remaining_reduction_to_1_3':max(0,1-1.3/ratio),
                       'binaries':{side:{'path':str(binary),'sha256':A.sha(binary)} for side,binary in binaries.items()}}
                if key in prior['samples']:
                    old = prior['samples'][key]
                    row['historical_joined30'] = {'source':prior['identity']['compiler_commit'],'cpu':prior['identity']['cpu'],
                                                'instruction_ratio':old['instruction_ratio'],'rc_instructions':old['medians']['rc']['instructions'],
                                                'current_rc_over_prior_rc':medians['rc']['instructions']/old['medians']['rc']['instructions']}
                state['samples'][key] = row;state.pop('inflight',None)
                state['summary31'] = summary(state['samples']);state['summary30'] = summary(state['samples'],True)
                save();print('measure',key,'RC/GC',ratio,'reduction_to_cap',row['remaining_reduction_to_1_3'],flush=True)
            if key not in state['counted']:
                binary = WORK / 'bin' / (binarykey+'.stats')
                run = PC.run_spec(p,binary,'entry-loops-counted-'+backend,state['schematic_declared'])
                run['argv'] = ['taskset','-c',str(M.CPU),*run['argv']]
                check = M.checked(p,run)
                ns = [json.loads(line.split(' ',1)[1]) for line in check['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
                assert check['ok'] and len(ns)==1,check
                n = ns[0]
                assert n['runtime']=='rc-v3-counting' and not n['saturated']
                assert n['heap_allocate']==n['retire'] and n['hold_acquire']==n['hold_release']
                assert n['owner_acquire']+n['heap_allocate']==n['owner_release']
                state['counted'][key] = {'check':check,'counts':n,'run':M.receipt(run),'binary_sha256':A.sha(binary)}
                save();print('counted',key,flush=True)
    identities()
    assert len(state['samples']) == len(state['counted']) == 62
    state['complete_diagnostic'] = True
    save();print('complete31 diagnostic; not full43 acceptance',flush=True)


if __name__ == '__main__': main()
