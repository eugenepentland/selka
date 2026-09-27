import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-flat/cumulative-19e';frozen=root.parent/'d9-rc-contract-astra/.tmp-rc/profile'
compiler=root.parent/'d9-rc-integration/.tmp-rc/install-history-flat/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(compiler)=='1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe'
expected=(root/'experiments/d9-rc-flat-destruction-20260926/expected.stdout').read_text()
result={'source_commit':'19e16e1d96112e9ccc741fa0c430ea97173a1032','compiler':str(compiler),'compiler_sha256':sha(compiler),'cpu':3,'builds':[],'backends':{}}
def save(): (work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
for backend in ('qbe','llvm'):
    for mode,suffix in [('rc','n12'),('stats','n12'),('rc','repeat')]:
        source=work/('binary_trees_n12_repeat.my' if suffix=='repeat' else 'binary_trees_n12.my')
        binary=work/f'{backend}-{mode}-{suffix}'
        command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir',str(work/f'cache-{backend}'),'--keep-symbols','--rc-runtime=stats' if mode=='stats' else '--rc-runtime']
        if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
        done=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)),check=True)
        manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
        assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
        result['builds'].append({'command':command,'sha256':sha(binary),'manifest':manifest,'stdout':done.stdout,'stderr':done.stderr});save()
        print('built',binary.name,sha(binary),flush=True)
    binaries={'rc':work/f'{backend}-rc-n12','gc':frozen/f'gap-allocator-{backend}-gc-n12'}
    samples=[]
    for i in range(3):
        for arm in (('rc','gc') if i%2==0 else ('gc','rc')):
            command=['taskset','-c','3','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[arm])]
            done=subprocess.run(command,text=True,capture_output=True,check=True);assert done.stdout==expected
            counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
            samples.append({'arm':arm,'command':command,'counters':counters,'stderr':done.stderr})
    done=subprocess.run([str(work/f'{backend}-stats-n12')],text=True,capture_output=True,check=True);assert done.stdout==expected
    counts=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '))
    assert counts['runtime']=='rc-v3-counting' and not counts['saturated']
    assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release']
    medians={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['arm']==arm) for arm in binaries}
    rss={}
    for arm,binary in binaries.items():
        command=['taskset','-c','3','/usr/bin/time','-f','%M',str(binary)]
        run=subprocess.run(command,text=True,capture_output=True,check=True);assert run.stdout==expected
        rss[arm]={'command':command,'max_rss_kib':int(run.stderr.strip())}
    result['backends'][backend]={'samples':samples,'medians':medians,'rc_over_gc':medians['rc']/medians['gc'],'counts':counts,'max_rss':rss,'binaries':{a:{'path':str(p),'sha256':sha(p)} for a,p in binaries.items()}};save()
    print(backend,medians,result['backends'][backend]['rc_over_gc'],counts,flush=True)
    for arm,binary in [('rc',work/f'{backend}-rc-repeat'),('gc',frozen/f'gap-allocator-{backend}-gc-repeat')]:
        prefix=work/f'{backend}-{arm}'
        command=['perf','record','-q','-e','cpu_core/instructions/u','-F','199','-o',str(prefix)+'.data','--','taskset','-c','3',str(binary)]
        run=subprocess.run(command,text=True,capture_output=True,check=True);assert run.stdout==expected*240
        for suffix,arguments in [('samples.txt',['script','-F','ip,sym,dso,period']),('report.txt',['report','--stdio','--no-children','--sort','symbol,dso','--percent-limit','0.3']),('stats.txt',['report','--stdio','--stats'])]:
            output=subprocess.run(['perf']+arguments+['-i',str(prefix)+'.data'],text=True,capture_output=True,check=True)
            Path(str(prefix)+'.'+suffix).write_text(output.stdout+output.stderr)
        result['backends'][backend][arm+'_profile']={'command':command,'sha256':sha(binary),'stderr':run.stderr};save()
        print('profiled',backend,arm,flush=True)
