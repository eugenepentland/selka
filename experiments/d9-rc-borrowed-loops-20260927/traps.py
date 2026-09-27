from pathlib import Path
import os,json,subprocess,hashlib
root=Path.cwd();w=root/'.tmp-borrow-loops';compiler=w/'install/bin/mylang'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'trap-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save():(w/'traps.json').write_text(json.dumps(r,indent=2)+'\n')
source='''record Node:
    text: bytes
    id: int
def selected(nodes: list[Node], key: int) -> Node:
    i = 0
    while i < 100000:
        if i == key:
            return nodes[i]
        i += 1
    return nodes[0]
def main(out: Stream) -> int:
    with arena():
        nodes = [Node(bytes([65]), 7)]
        out.print("before")
        result = selected(nodes, KEY)
        out.print(result.id)
    return 0
'''
for case,key,option,trap in [('bounds',3,None,'R_LIST_BOUNDS'),('steps',-1,'--max-steps=1000','R_STEP_LIMIT'),('frames',3,'--max-frames=1','R_FRAME_LIMIT')]:
 path=w/f'{case}.my';path.write_text(source.replace('KEY',str(key)))
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   binary=w/f'{case}-{mode}-{backend}';cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(path),'-o',str(binary),'--cache-dir',str(w/'trap-cache'),f'--backend={backend}','--mode=Debug']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   if option:cmd+=[option]
   d=subprocess.run(cmd,env=env,text=True,capture_output=True);row={'case':case,'backend':backend,'mode':mode,'build_command':cmd,'build_exit':d.returncode,'build_stderr':d.stderr};r['runs'].append(row);save();assert d.returncode==0,row
   manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());row['manifest']=manifest;assert manifest['backend']==backend
   e=dict(env)
   e['MYLANG_OPTIONS']=' '.join(x for x in ('--gc-stress' if mode=='gc' else '', option or '') if x)
   row['runtime_options']=e['MYLANG_OPTIONS']
   d=subprocess.run([str(binary)],env=e,text=True,capture_output=True,timeout=30);row.update(exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());save();assert d.returncode==1 and d.stdout=='before\n' and trap in d.stderr,row
   if mode=='rc':
    c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in d.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   save();print(case,mode,backend,'pass',row.get('counts',{}),flush=True)
