#!/usr/bin/env python3
"""Correctness-gated, common-iteration runtime measurements. See README.md."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import shutil
import statistics
import subprocess
import sys
import time
import uuid
from oracle import CASES, checksum
from build_compiler import validate_receipt
HERE = Path(__file__).resolve().parent
ARMS = ('my-llvm','my-qbe','rust','go','zig-safe','zig-fast')
TIMING_LOCK = Path('/home/epentland/.cache/mylang/runtime-parity-timing.lock')


@contextmanager
def timing_lock():
    TIMING_LOCK.parent.mkdir(parents=True, exist_ok=True)
    with TIMING_LOCK.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def validate(done, expected, rss=False):
    if done.returncode != 0:
        raise RuntimeError(f'guest exit {done.returncode}: {done.stderr}')
    if rss:
        if re.fullmatch(r'RUNTIME_RSS_KIB=[0-9]+\n',done.stderr) is None:
            raise RuntimeError(f'unexpected memory probe stderr: {done.stderr!r}')
    elif done.stderr:
        raise RuntimeError(f'unexpected guest stderr: {done.stderr!r}')
    match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', done.stdout)
    if not match:
        raise RuntimeError(f'malformed guest output: {done.stdout!r}')
    value, ns = map(int, match.groups())
    if value != expected or ns <= 0:
        raise RuntimeError(f'guest result {value}/{ns}; expected checksum {expected} and positive ns')
    return {'checksum':value, 'kernel_ns':ns, 'exit_status':done.returncode}

def verify_identity(saved, current):
    if saved != current:
        raise RuntimeError('stale or incompatible build manifest; rebuild without --skip-build')

def artifact_hashes(binaries, work):
    return {**{arm:digest(path) for arm,path in binaries.items()},'native_clock.o':digest(work/'native_clock.o')}

def verify_manifest(path, identity, binaries, work):
    saved = json.loads(path.read_text())
    verify_identity(saved['identity'],identity)
    verify_identity(saved['binary_hashes'],artifact_hashes(binaries,work))

def runtime_environment():
    env = {key:value for key,value in os.environ.items() if not key.startswith('MYLANG_')}
    for key in ('GODEBUG','GOEXPERIMENT','MYLANG_OPTIONS','MYLANG_GC_STRESS','MYLANG_GC_STEP','MYLANG_STRESS','MYLANG_STEPS','RUSTFLAGS','CFLAGS','CXXFLAGS','RUSTC_BOOTSTRAP','CGO_CFLAGS','CGO_CPPFLAGS','CGO_CXXFLAGS','CGO_LDFLAGS','LDFLAGS','MYLANG_QBE','MYLANG_ZIG','MYLANG_RUNTIME'):
        env.pop(key,None)
    env.update(GOMAXPROCS='1',GOGC='100',GOMEMLIMIT='off',GOAMD64='v1',GOFLAGS='',GOEXPERIMENT='',GOTOOLCHAIN='local')
    return env

def invoke(binary, case, size, iterations, seed, cpu, expected, rss=False):
    cmd = ['taskset','-c',str(cpu),str(binary),case,str(size),str(iterations),str(seed)]
    if rss:
        cmd = ['/usr/bin/time','-f','RUNTIME_RSS_KIB=%M',*cmd]
    with timing_lock():
        start = time.perf_counter_ns()
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=120, env=runtime_environment())
        wall = time.perf_counter_ns()-start
    result = validate(done, expected, rss=rss)
    result['process_wall_ns'] = wall
    if rss:
        matches = re.findall(r'^RUNTIME_RSS_KIB=(\d+)$', done.stderr, re.M)
        if len(matches) != 1:
            raise RuntimeError('missing peak RSS measurement')
        result['peak_rss_kib'] = int(matches[0])
    return result

def configuration(args):
    receipt_path = args.compiler_receipt.resolve()
    receipt = json.loads(receipt_path.read_text())
    validate_receipt(receipt, args.mylang, artifacts=True)
    tools = {'cc':args.cc,'mylang':args.mylang,'rust':args.rustc,'go':args.go,'zig':args.zig}
    tools = {key:str(Path(shutil.which(value) or value).absolute()) for key,value in tools.items()}
    rust_probe = subprocess.run([tools['rust'],'--print','sysroot'],capture_output=True,text=True,timeout=30,env=runtime_environment())
    actual_rust = Path(rust_probe.stdout.strip())/'bin/rustc'
    if rust_probe.returncode != 0 or not actual_rust.is_file(): raise RuntimeError('cannot resolve actual rustc compiler from supplied executable')
    versions = {}
    for key,path in tools.items():
        if key == 'mylang':
            versions[key] = {'path':path,'sha256':digest(path),'source_revision':receipt['source_revision'],'version':'unsupported; recorded compiler build receipt used'}
            continue
        command = [path, 'version' if key in ('go','zig') else '--version']
        done = subprocess.run(command,capture_output=True,text=True,timeout=30,env=runtime_environment())
        if done.returncode: raise RuntimeError(f'{key} version query failed: {done.stderr}')
        hash_path = str(actual_rust.resolve()) if key == 'rust' else path
        versions[key] = {'path':path,'compiler_path':hash_path,'sha256':digest(hash_path),'invocation_sha256':digest(path),'version':(done.stdout+done.stderr).strip(),'version_status':done.returncode}
    compiler_dir = Path(tools['mylang']).resolve().parent
    qbe = compiler_dir/'qbe'
    if not qbe.is_file(): qbe = Path(shutil.which('qbe') or '')
    if not qbe.is_file(): raise RuntimeError('cannot locate QBE compiler asset')
    assets = [qbe, *sorted((compiler_dir.parent/'lib/mylang-runtime').rglob('*'))]
    asset_hashes = {str(path):digest(path) for path in assets if path.is_file()}
    p = HERE/'ports'
    binaries = {arm:args.work/arm for arm in ARMS}
    commands = {}
    for arm in ARMS:
        out = str(binaries[arm])
        if arm.startswith('my-'):
            flags = ['--mode','ReleaseFast','--backend',arm[3:]]
            if arm == 'my-llvm': flags += ['--llvm-opt','3','--lto']
            commands[arm] = [tools['mylang'],'build',str(p/'main.my'),'-o',out,'--cache-dir',str(args.work/'mycache'),'--link',str(args.work/'native_clock.o'),'--zig',tools['zig'],'--qbe',str(qbe),*flags]
        elif arm == 'rust': commands[arm] = [tools['rust'],'-O','--edition','2021',str(p/'main.rs'),'-o',out]
        elif arm == 'go': commands[arm] = [tools['go'],'build','-o',out,str(p/'main.go')]
        else: commands[arm] = [tools['zig'],'build-exe',str(p/'main.zig'),'-lc','-O','ReleaseSafe' if arm == 'zig-safe' else 'ReleaseFast',f'-femit-bin={out}']
    sources = {str(path.relative_to(HERE)):digest(path) for path in [HERE/'CONTRACT.md', HERE/'oracle.py', HERE/'runner.py', HERE/'build_compiler.py', *sorted(p.iterdir())] if path.is_file()}
    identity = {'candidate_id':args.candidate_id,'source_revision':receipt['source_revision'],
                'compiler_build_receipt':{'path':str(receipt_path),'sha256':digest(receipt_path),'receipt':receipt},
                'tools':versions,'sources':sources,'commands':commands,'installed_assets':asset_hashes,'build_environment':{key:runtime_environment().get(key) for key in ('GOMAXPROCS','GOGC','GOMEMLIMIT','GOAMD64','GOFLAGS','GOEXPERIMENT','GOTOOLCHAIN','RUSTFLAGS','CFLAGS','CXXFLAGS','CGO_CFLAGS','CGO_LDFLAGS','MYLANG_OPTIONS')},'build_wrapper':str(HERE.parents[1]/'scripts/build-slot.sh'),'clock_build':[tools['cc'],'-O2','-c',str(p/'native_clock.c'),'-o',str(args.work/'native_clock.o')]}
    probe_command = [tools['zig'],'cc','-###','-c','-x','c','/dev/null']
    probe = subprocess.run(probe_command,capture_output=True,text=True,timeout=30,env=runtime_environment())
    if probe.returncode: raise RuntimeError('Zig/Clang target policy probe failed')
    probe_text = probe.stdout+probe.stderr
    identity['target_policy'] = {'my-llvm':'default Zig/Clang-derived CPU/features; first target CPU and merged target features','my-qbe':'amd64_sysv','rust':'rustc -O default x86_64','go':'GOAMD64=v1','zig-safe':'default host','zig-fast':'default host','policy_note':'Optimized default build policies; instruction sets are not matched across arms. No forced target tuning or disabled MyLang checks.','llvm_target_probe':{'command':probe_command,'target_cpu_entries':re.findall(r"\"-target-cpu\" \"([^\"]+)\"",probe_text),'enabled_features':re.findall(r"\"-target-feature\" \"(\+[^\"]+)\"",probe_text),'feature_entries':re.findall(r"\"-target-feature\" \"([^\"]+)\"",probe_text),'exit_status':probe.returncode}}
    identity['wrapper_sha256'] = digest(identity['build_wrapper'])
    identity['actual_clock_build'] = [identity['build_wrapper'],'build',*identity['clock_build']]
    identity['private_cache_environment'] = {'TMPDIR':str(args.work/'tmp'),'GOCACHE':str(args.work/'gocache'),'ZIG_LOCAL_CACHE_DIR':str(args.work/'zigcache'),'ZIG_GLOBAL_CACHE_DIR':str(args.work/'zig-global-cache')}
    identity['actual_build_commands'] = {arm:[identity['build_wrapper'],'build',*command] for arm,command in commands.items()}
    return binaries, commands, identity

def cpu_snapshot():
    result = {}
    for line in Path('/proc/stat').read_text().splitlines():
        fields = line.split()
        if fields and re.fullmatch(r'cpu[0-9]+',fields[0]):
            ticks = list(map(int,fields[1:9]))
            result[int(fields[0][3:])] = {'total':sum(ticks),'idle':ticks[3]+ticks[4]}
    return result

def cpu_environment(cpu, before, after):
    directory = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    sibling_file = directory/'topology/thread_siblings_list'
    sibling_text = sibling_file.read_text().strip() if sibling_file.exists() else str(cpu)
    siblings = []
    for part in sibling_text.split(','):
        bounds = part.split('-')
        siblings.extend(range(int(bounds[0]),int(bounds[-1])+1))
    busy = {}
    for core in siblings:
        if core in before and core in after:
            total = after[core]['total']-before[core]['total']
            idle = after[core]['idle']-before[core]['idle']
            busy[str(core)] = 100*(total-idle)/total if total > 0 else None
    frequency = {}
    for name in ('scaling_governor','scaling_driver','scaling_min_freq','scaling_max_freq','scaling_cur_freq'):
        path = directory/'cpufreq'/name
        frequency[name] = path.read_text().strip() if path.exists() else None
    warnings = [f'Sibling CPU {core} was {percent:.1f}% busy during sampling; interference may affect results.' for core,percent in busy.items() if int(core)!=cpu and percent is not None and percent > 5]
    return {'thread_siblings':sibling_text,'per_core_busy_percent_sampling':busy,'frequency':frequency,'warnings':warnings,
            'warning':'Sibling reservation is operator-managed; busy counters record average load and cannot exclude short interference.'}

def execute(args):
    if args.cpu not in os.sched_getaffinity(0): raise RuntimeError(f'CPU {args.cpu} unavailable')
    args.work.mkdir(parents=True,exist_ok=True)
    binaries, commands, identity = configuration(args)
    manifest = args.work/'manifest.json'
    build_logs = []
    if args.skip_build:
        verify_manifest(manifest,identity,binaries,args.work)
        build_logs = json.loads(manifest.read_text()).get('build_logs',[])
    else:
        build_env = {**runtime_environment(), **identity['private_cache_environment']}
        (args.work/'tmp').mkdir(exist_ok=True)
        done = subprocess.run(identity['actual_clock_build'],env=build_env,check=True,capture_output=True,text=True,timeout=120)
        build_logs.append({'arm':'clock','command':identity['actual_clock_build'],'exit_status':done.returncode,'stdout':done.stdout,'stderr':done.stderr})
        for arm,command in commands.items():
            done = subprocess.run([identity['build_wrapper'],'build',*command],cwd=HERE/'ports',env=build_env,capture_output=True,text=True,timeout=1800)
            build_logs.append({'arm':arm,'command':identity['actual_build_commands'][arm],'exit_status':done.returncode,'stdout':done.stdout,'stderr':done.stderr})
            if done.returncode or not binaries[arm].exists(): raise RuntimeError(f'{arm} build failed: {done.stdout}\n{done.stderr}')
        verify_identity(identity,configuration(args)[2])
        manifest.write_text(json.dumps({'identity':identity,'binary_hashes':artifact_hashes(binaries,args.work),'build_logs':build_logs},indent=2)+'\n')
    (args.work/'build-log.json').write_text(json.dumps(build_logs,indent=2)+'\n')
    before_hashes = artifact_hashes(binaries,args.work)
    probes = []
    for case in CASES:
        for size,seed,iters in ((2,1,1),(3,42,7),(17,999983,31)):
            expected = checksum(case,size,iters,seed)
            for arm in ARMS:
                probes.append({'arm':arm,'case':case,'size':size,'seed':seed,'iterations':iters,**invoke(binaries[arm],case,size,iters,seed,args.cpu,expected)})
    selected = args.only or list(CASES)
    plans, pilots = [], []
    for case in selected:
        for label,size in (('small',64),('large',1024 if case.startswith('mutate') else 4096)):
            count = 31
            while True:
                expected = checksum(case,size,count,42)
                results = [invoke(binaries[arm],case,size,count,42,args.cpu,expected) for arm in ARMS]
                pilots.append({'case':case,'size':size,'iterations':count,'arms':dict(zip(ARMS,results))})
                fastest = min(r['kernel_ns'] for r in results)
                slowest = max(r['kernel_ns'] for r in results)
                if args.quick or fastest >= args.target_ms*1000000 or slowest >= args.max_sample_ms*1000000 or count >= args.max_iterations: break
                growth = min(20,args.target_ms*1000000/fastest,args.max_sample_ms*1000000/slowest)
                next_count = min(args.max_iterations,max(count+1,int(count*growth)))
                if next_count <= count: break
                count = next_count
            plans.append({'case':case,'profile':label,'size':size,'iterations':count,'seed':42,'expected':checksum(case,size,count,42),'calibration':{'fastest_ns':fastest,'slowest_ns':slowest,'target_ns':args.target_ms*1000000,'slowest_cap_ns':args.max_sample_ms*1000000,'iteration_cap':args.max_iterations,'limited':not args.quick and fastest < args.target_ms*1000000}})
    samples, warmups, memory = [], [], []
    cpu_before = cpu_snapshot()
    load_before = os.getloadavg()
    for plan in plans:
        for round_index in range(-args.warmups,args.rounds):
            order = list(ARMS)
            random.Random(f'{plan["case"]}/{plan["size"]}/{round_index}').shuffle(order)
            for arm in order:
                result = invoke(binaries[arm],plan['case'],plan['size'],plan['iterations'],42,args.cpu,plan['expected'])
                (warmups if round_index < 0 else samples).append({**plan,'arm':arm,'round':round_index,**result})
        for arm in ARMS:
            memory.append({**plan,'arm':arm,**invoke(binaries[arm],plan['case'],plan['size'],plan['iterations'],42,args.cpu,plan['expected'],rss=True)})
    cpu_after = cpu_snapshot()
    after_hashes = artifact_hashes(binaries,args.work)
    verify_identity(before_hashes,after_hashes)
    verify_identity(identity,configuration(args)[2])
    environment = {'platform':platform.platform(),'cpu':args.cpu,**cpu_environment(args.cpu,cpu_before,cpu_after),'loadavg_before':load_before,'loadavg_after':os.getloadavg(),'GOMAXPROCS':'1','GOGC':'100','GOMEMLIMIT':'off','GOAMD64':'v1','GOFLAGS':'','GOEXPERIMENT':'','GOTOOLCHAIN':'local','removed_environment':['GODEBUG','MYLANG_*','RUSTFLAGS','CFLAGS','CXXFLAGS','RUSTC_BOOTSTRAP','CGO_CFLAGS','CGO_CPPFLAGS','CGO_CXXFLAGS','CGO_LDFLAGS','LDFLAGS'],'cpuinfo':Path('/proc/cpuinfo').read_text()}
    report = {'schema':'mylang-runtime-v2','measurement_session_id':str(uuid.uuid4()),'status':'smoke' if args.quick else ('complete' if set(selected)==set(CASES) else 'subset'),'profile':'smoke' if args.quick else 'baseline','coverage':selected,'rounds':args.rounds,'warmup_rounds':args.warmups,'identity':identity,'binary_hashes':before_hashes,'binary_hashes_after':after_hashes,'identity_after':identity,'environment':environment,'build_logs':build_logs,'qualification':probes,'pilots':pilots,'plans':plans,'warmups':warmups,'samples':samples,'memory':memory}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    report['summary'] = summarize(report)
    for warning in environment['warnings']: print('WARNING: '+warning,file=sys.stderr)
    temporary = args.output.with_suffix(args.output.suffix+'.tmp')
    temporary.write_text(json.dumps(report,indent=2)+'\n')
    temporary.replace(args.output)
    args.output.with_suffix('.md').write_text(markdown_report(report)+'\n')
    for plan in plans:
        for arm in ARMS:
            values = [s['kernel_ns'] for s in samples if s['arm']==arm and s['case']==plan['case'] and s['size']==plan['size']]
            print(f'{plan["case"]}/{plan["profile"]} {arm}: {statistics.median(values):.0f} ns ({plan["iterations"]} iterations)')

def summarize(report):
    rows = []
    for plan in report['plans']:
        chosen = [s for s in report['samples'] if s['case']==plan['case'] and s['size']==plan['size']]
        go = {s['round']:s['kernel_ns'] for s in chosen if s['arm']=='go'}
        for arm in ARMS:
            samples = [s for s in chosen if s['arm']==arm]
            ns_per_op = [s['kernel_ns']/plan['iterations'] for s in samples]
            ratios = [s['kernel_ns']/go[s['round']] for s in samples]
            rng = random.Random(f"{plan['case']}/{plan['size']}/{arm}/bootstrap")
            medians = sorted(statistics.median(rng.choices(ratios,k=len(ratios))) for _ in range(2000))
            rows.append({'case':plan['case'],'size':plan['size'],'profile':plan['profile'],'arm':arm,'iterations':plan['iterations'],
                         'median_ns_per_op':statistics.median(ns_per_op),'min_ns_per_op':min(ns_per_op),'max_ns_per_op':max(ns_per_op),
                         'median_paired_ratio_to_go':statistics.median(ratios),'paired_bootstrap_95_interval':[medians[49],medians[1949]]})
    return rows

def markdown_report(report):
    lines = [f"Runtime microbenchmark result: **{report['status']}**.", '',
             f"CPU {report['environment']['cpu']}; {report['rounds']} sample rounds; {report['warmup_rounds']} warmup rounds. Kernel time excludes initialization and final formatting. ns/op means one contract iteration (including snapshot copy for mutate_shared).", '',
             report['identity']['target_policy']['policy_note'], '',
             'Ratios pair each arm with Go in the same round. Intervals are deterministic 2,000-resample percentile bootstrap intervals for the median paired ratio. Small round counts cannot provide useful uncertainty estimates. Min/max show the raw observed spread; no overall score pools different workloads.', '',
             '| Case / size | Arm | Iterations | Median ns/op | Min–max ns/op | Ratio to Go | 95% paired interval |',
             '|---|---|---:|---:|---:|---:|---:|']
    for row in report['summary']:
        low,high = row['paired_bootstrap_95_interval']
        lines.append(f"| {row['case']} / {row['profile']} | {row['arm']} | {row['iterations']} | {row['median_ns_per_op']:.2f} | {row['min_ns_per_op']:.2f}–{row['max_ns_per_op']:.2f} | {row['median_paired_ratio_to_go']:.3f} | {low:.3f}–{high:.3f} |")
    limited = [f"{p['case']}/{p['profile']}" for p in report['plans'] if p['calibration']['limited']]
    if limited:
        lines += ['', 'Calibration hit a slowest-arm or iteration cap before the fastest arm reached its target: '+', '.join(limited)+'. Inspect raw kernel durations before interpreting these cases.']
    lines += ['', 'Peak RSS is measured in separate processes and appears in the companion JSON. Process wall time is secondary. '+report['environment']['warning']]
    return '\n'.join(lines)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mylang',default=str(HERE.parents[1]/'zig-out/bin/mylang'))
    parser.add_argument('--candidate-id',required=True)
    parser.add_argument('--compiler-receipt',type=Path,required=True)
    parser.add_argument('--cc',default='cc')
    parser.add_argument('--rustc',default='/home/epentland/.cargo/bin/rustc')
    parser.add_argument('--go',default='go'); parser.add_argument('--zig',default='zig')
    parser.add_argument('--cpu',type=int,default=2)
    parser.add_argument('--rounds',type=int,default=15); parser.add_argument('--warmups',type=int,default=3)
    parser.add_argument('--target-ms',type=float,default=50)
    parser.add_argument('--max-sample-ms',type=float,default=2000)
    parser.add_argument('--max-iterations',type=int,default=10000000)
    parser.add_argument('--only',nargs='+',choices=CASES)
    parser.add_argument('--quick',action='store_true'); parser.add_argument('--profile',choices=('baseline','smoke'),default='baseline')
    parser.add_argument('--skip-build',action='store_true')
    parser.add_argument('--work',type=Path,default=HERE.parents[1]/'.mylang-cache/runtime-baseline'); parser.add_argument('--output',type=Path,default=HERE/'results/runtime.json')
    args = parser.parse_args()
    args.work = args.work.resolve(); args.output = args.output.resolve()
    args.quick = args.quick or args.profile == 'smoke'
    if args.rounds < 1 or args.warmups < 0 or args.target_ms < 30 or args.max_sample_ms < args.target_ms or args.max_iterations < 31: parser.error('invalid rounds/warmups/target')
    try: execute(args)
    except (RuntimeError,OSError,ValueError,subprocess.TimeoutExpired,subprocess.CalledProcessError) as error:
        print(f'FAILED (no baseline produced): {error}',file=sys.stderr)
        return 1
    return 0
if __name__ == '__main__': sys.exit(main())
