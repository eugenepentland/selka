import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd(); work=root/'.tmp-plain'; sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
compilers={arm:work/f'install-{arm}/bin/mylang' for arm in ('before','after')}
result={'baseline_commit':'2d41fb4f49eda4dbf318cabc78fe497361cf1ca9','production_sha256':sha(root/'src/native_rc_values.c'),'compiler_sha256':{a:sha(p) for a,p in compilers.items()},'builds':[],'backends':{}}
def save(): (work/'measurements.json').write_text(json.dumps(result,indent=2)+'\n')
for backend in ('qbe','llvm'):
    binaries={}
    for arm,compiler in compilers.items():
        for mode in ('rc','stats'):
            source=work/'nbody_10000.my'; binary=work/f'nbody-{backend}-{arm}-{mode}'
            command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir',str(work/f'cache-{backend}'),'--keep-symbols','--rc-runtime=stats' if mode=='stats' else '--rc-runtime']
            if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
            done=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)),check=True)
            manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
            result['builds'].append({'arm':arm,'mode':mode,'command':command,'sha256':sha(binary),'manifest':manifest,'stdout':done.stdout,'stderr':done.stderr});save()
            binaries[(arm,mode)]=binary
    samples=[];outputs=[];counts={}
    for i in range(5):
        for arm in (('before','after') if i%2==0 else ('after','before')):
            command=['taskset','-c','3','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[(arm,'rc')])]
            done=subprocess.run(command,text=True,capture_output=True,check=True);outputs.append(done.stdout)
            counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
            samples.append({'arm':arm,'command':command,'counters':counters,'stderr':done.stderr})
    for arm in compilers:
        done=subprocess.run(['taskset','-c','3',str(binaries[(arm,'stats')])],text=True,capture_output=True,check=True);outputs.append(done.stdout)
        counts[arm]=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '))
    assert len(set(outputs))==1 and counts['before']==counts['after']
    assert counts['after']['heap_allocate']==counts['after']['retire'] and counts['after']['hold_acquire']==counts['after']['hold_release']
    medians={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['arm']==arm) for arm in compilers}
    result['backends'][backend]={'samples':samples,'medians':medians,'after_over_before':medians['after']/medians['before'],'counts':counts,'stdout':outputs[0]};save()
    print(backend,medians,result['backends'][backend]['after_over_before'],flush=True)
