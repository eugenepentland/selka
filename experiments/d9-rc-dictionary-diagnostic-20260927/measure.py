"""Unchanged dict_count on frozen joined RC versus immutable accepted GC."""
import importlib.util, json, os, statistics, subprocess, hashlib
from pathlib import Path
root=Path.cwd();work=root/'.tmp-rc/dict-audit';os.environ['PC_WORK']=str(work)
os.environ['TMPDIR']=str(root/'.tmp-rc/tmp')
os.environ['ZIG_LOCAL_CACHE_DIR']=str(root/'.zig-cache-rc')
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
compiler=root/'.tmp-rc/install-flat-retain-joined/bin/mylang'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
base=root.parent/'d9-rc-performance/.tmp-rc-performance'
accepted=json.loads((base/'gc-builds.json').read_text())
p=next(p for p in pc.programs() if p['id']=='parity/micro/dict_count')
assert sha(p['src'])==accepted['inputs'][str(root.parent/'d9-rc-performance'/Path(p['src']).relative_to(root))]
assert sha(compiler)=='12a3693929913d50385248a5938fcf57694de8a3538e65f150432c998936d268'
result={'source':'d1d8b3c46ac41e832410a03aad49a5a6a1a54b07','compiler_sha256':sha(compiler),'driver_sha256':sha(__file__),'program':p,'input_sha256':sha(p['src']),'expected_sha256':sha(p['expected_path']),'cpu':10,'builds':{},'samples':{},'counts':{}}
def save(): (work/'measurements.json').write_text(json.dumps(result,indent=2)+'\n')
def run(command,**kwargs):
    r=subprocess.run(command,capture_output=True,timeout=600,**kwargs)
    if r.returncode:raise RuntimeError((command,r.returncode,r.stderr.decode()))
    return r
for backend in ['qbe','llvm']:
    for mode in ['production','stats']:
        binary=work/f'dict-{backend}-{mode}'
        command,cwd=pc.build_command(p,str(compiler),backend,binary,work/'cache')
        command=[str(root/'scripts/build-slot.sh'),'build',*command,'--keep-symbols','--rc-runtime'+('=stats' if mode=='stats' else '')]
        r=run(command,cwd=cwd,env=pc.clean_env())
        result['builds'][backend+'-'+mode]={'command':command,'stderr':r.stderr.decode(),'sha256':sha(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())};save()
    gc=base/'bin/gc'/f"{p['build_key']}.{backend}";assert sha(gc)==accepted['builds'][f"{p['build_key']}.{backend}"]['sha256']
    binaries={'gc':gc,'rc':work/f'dict-{backend}-production'}
    rows=[]
    for repeat in range(3):
        for arm in (['gc','rc'] if repeat%2==0 else ['rc','gc']):
            command=['taskset','-c','10','perf','stat','-x,','-e','cpu_core/instructions/u','--',str(binaries[arm])]
            r=run(command,cwd=Path(p['src']).parent,env=pc.clean_env())
            assert r.stdout==Path(p['expected_path']).read_bytes()
            events=[line.split(',') for line in r.stderr.decode().splitlines() if ',cpu_core/instructions/u,' in line]
            assert len(events)==1 and float(events[0][4])>=99.9
            rows.append({'arm':arm,'repeat':repeat,'command':command,'stdout':r.stdout.decode(),'stderr':r.stderr.decode(),'instructions':int(events[0][0]),'binary_sha256':sha(binaries[arm])})
    medians={arm:statistics.median(r['instructions'] for r in rows if r['arm']==arm) for arm in binaries}
    result['samples'][backend]={'rows':rows,'medians':medians,'rc_over_gc':medians['rc']/medians['gc']};save();print(backend,medians,result['samples'][backend]['rc_over_gc'],flush=True)
    command=['taskset','-c','10',str(work/f'dict-{backend}-stats')]
    r=run(command,cwd=Path(p['src']).parent,env=pc.clean_env());assert r.stdout==Path(p['expected_path']).read_bytes()
    counts=[json.loads(line.split(' ',1)[1]) for line in r.stderr.decode().splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    assert len(counts)==1;count=counts[0]
    assert not count['saturated'] and count['heap_allocate']==count['retire'] and count['hold_acquire']==count['hold_release'] and count['owner_acquire']+count['heap_allocate']==count['owner_release']
    result['counts'][backend]={'command':command,'stdout':r.stdout.decode(),'stderr':r.stderr.decode(),'counts':count};save();print('counts',backend,count,flush=True)
assert result['counts']['qbe']['counts']==result['counts']['llvm']['counts']
