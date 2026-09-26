import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-flat';frozen=root.parent/'d9-rc-contract-astra/.tmp-rc/profile';compiler=root/'zig-out/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
expected=(work/'expected.stdout').read_text()
source=root/'experiments/d9-rc-flat-destruction-20260926/binary_trees_n12.my'
result={'compiler_sha256':sha(compiler),'source_sha256':sha(source),'production_sha256':sha(root/'src/native_rc_walk.c'),'builds':[],'backends':{}}
for backend in ('qbe','llvm'):
    for mode in ('rc','stats'):
        binary=work/f'candidate-{backend}-{mode}-n12'
        command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir',str(work/f'candidate-cache-{backend}'),'--keep-symbols','--rc-runtime=stats' if mode=='stats' else '--rc-runtime']
        if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
        done=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)),check=True)
        manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
        assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
        result['builds'].append({'command':command,'stdout':done.stdout,'stderr':done.stderr,'sha256':sha(binary),'manifest':manifest})
        (work/'candidate.json').write_text(json.dumps(result,indent=2)+'\n')
    binaries={'before':frozen/f'inert-return-final-{backend}-rc-n12','after':work/f'candidate-{backend}-rc-n12','gc':frozen/f'gap-allocator-{backend}-gc-n12'}
    samples=[]
    for i in range(5):
        for arm in (('before','after','gc') if i%2==0 else ('gc','after','before')):
            command=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[arm])]
            done=subprocess.run(command,text=True,capture_output=True,check=True)
            assert done.stdout==expected
            counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
            samples.append({'arm':arm,'command':command,'counters':counters,'stderr':done.stderr})
    counts={}
    for arm,binary in [('before',frozen/f'inert-return-final-{backend}-stats-n12'),('after',work/f'candidate-{backend}-stats-n12')]:
        done=subprocess.run(['taskset','-c','2',str(binary)],text=True,capture_output=True,check=True)
        assert done.stdout==expected
        counts[arm]=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '))
    assert counts['before']==counts['after']
    medians={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['arm']==arm) for arm in binaries}
    result['backends'][backend]={'samples':samples,'medians':medians,'counts':counts,'after_over_before':medians['after']/medians['before'],'after_over_gc':medians['after']/medians['gc'],'binary_sha256':{arm:sha(p) for arm,p in binaries.items()}}
    (work/'candidate.json').write_text(json.dumps(result,indent=2)+'\n')
    print(backend,medians,result['backends'][backend]['after_over_before'],flush=True)
