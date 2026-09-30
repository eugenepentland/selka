import hashlib,json,os,shutil,struct,subprocess
from pathlib import Path
own=Path(__file__).resolve().parents[2]
work=Path(__file__).resolve().parent
root=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-next-closeout-20260929')
project=root/'.tmp-rc-quick/lox/benchmarks/lox/ports/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(own/'.tmp'),ZIG_LOCAL_CACHE_DIR=str(own/'.zig-local-cache'),ZIG_GLOBAL_CACHE_DIR=str(own/'.zig-global-cache'),MYLANG_MEMORY_LIMIT='8G')
def allocated(path):
    data=path.read_bytes();h=struct.unpack_from('<16sHHIQQQIHHHHHH',data)
    assert h[0][:6]==b'\x7fELF\x02\x01'
    ss=[struct.unpack_from('<IIQQQQIIQQ',data,h[6]+n*h[11]) for n in range(h[12])]
    names=ss[h[13]];names=data[names[4]:names[4]+names[5]];result={}
    for s in ss:
        if s[2]&2:
            name=names[s[0]:].split(b'\0',1)[0].decode();p=b'' if s[1]==8 else data[s[4]:s[4]+s[5]]
            result[name]=[s[1],s[2],s[3],s[5],hashlib.sha256(p).hexdigest()]
    return result
sources={str(p.relative_to(project)):sha(p) for p in project.rglob('*.my')}
receipt={'source_candidate':'3226f1d66b08734824e5c799c25a9c7ed4a69438','source_control':'80dd51906c97ae76bf208474ac48c9baac3a11cd','project':str(project),'project_sources':sources,'sides':{}}
for side,tag in [('control','m17-codex'),('candidate','phase-b-publish-combined')]:
    src=root/'.tmp-rc-quick/bin'/tag;dest=work/side;dest.mkdir(exist_ok=True)
    for name in ['compiler.json','lox.llvm','lox.llvm.qbe-manifest.json']:
        shutil.copy2(src/name,dest/name)
    compiler=json.loads((dest/'compiler.json').read_text());assert sha(Path(compiler['compiler']))==compiler['sha256']
    original=dest/'lox.llvm';output=dest/'lox.symbols'
    cmd=[str(own/'scripts/build-slot.sh'),'build',compiler['compiler'],'build','main.my','--project','-o',str(output),'--backend','llvm','--llvm-opt','3','--lto','--rc-runtime','--keep-symbols','--cache-dir',str(dest/'cache')]
    print(side,'build',flush=True);done=subprocess.run(cmd,cwd=project,env=env,capture_output=True)
    (dest/'build.stdout').write_bytes(done.stdout);(dest/'build.stderr').write_bytes(done.stderr)
    row={'original_path':str(src/'lox.llvm'),'original_sha256':sha(original),'compiler':compiler,'command':cmd,'status':done.returncode};receipt['sides'][side]=row
    (work/'inputs.json').write_text(json.dumps(receipt,indent=2)+'\n');assert done.returncode==0,done.stderr.decode(errors='replace')
    row['symbol_binary_sha256']=sha(output);a,b=allocated(original),allocated(output);row['allocated_sections_equal']=a==b;row['allocated_sections']=a
    if a!=b:row['allocated_differences']={k:[a.get(k),b.get(k)] for k in a.keys()|b.keys() if a.get(k)!=b.get(k)}
    print(side,'allocated identical',a==b,flush=True)
    (work/'inputs.json').write_text(json.dumps(receipt,indent=2)+'\n');assert a==b,row['allocated_differences']
    for name,cmd in [('symbols',['nm','-n','-S',str(output)]),('assembly',['objdump','-d','--no-show-raw-insn',str(output)])]:
        (dest/name).write_bytes(subprocess.check_output(cmd))
assert sources=={str(p.relative_to(project)):sha(p) for p in project.rglob('*.my')}
shutil.copy2(root/'.tmp-rc-quick/lox-scripts/invocation.n30000.lox',work/'invocation.n30000.lox')
receipt['input_sha256']=sha(work/'invocation.n30000.lox')
(work/'inputs.json').write_text(json.dumps(receipt,indent=2)+'\n')
