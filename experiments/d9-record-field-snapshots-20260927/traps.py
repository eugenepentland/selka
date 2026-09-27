from pathlib import Path
import os,json,subprocess,hashlib
root=Path.cwd();w=root/'.tmp-arena-snapshot';compiler=w/'install/bin/mylang'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'))
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save():(w/'traps.json').write_text(json.dumps(r,indent=2)+'\n')
base='''record State:
    items: list[int]
    count: int
HELPER
def change(state: mut State):
    state.items.append(RHS)
def main(out: Stream) -> int:
    items = [7]
    with arena():
        state = State(items, INITIAL)
        saved = state
        out.print("before")
        change(mut state)
        out.print(saved.count)
    return 0
'''
for case,helper,rhs,initial,options,trap in [
 ('overflow','', 'state.count + 1','9223372036854775807','','R_OVERFLOW'),
 ('budget','def grow() -> int:\n    items = [0]\n    for i in range(1000000):\n        items.append(i)\n    return len(items)','grow()','41','','R_MEMORY_BUDGET'),
 ('frames','def recursive(n: int) -> int:\n    if n == 0:\n        return 42\n    return recursive(n - 1)','recursive(10)','41','--max-frames=3','R_FRAME_LIMIT'),
 ('steps','def recursive(n: int) -> int:\n    if n == 0:\n        return 42\n    return recursive(n - 1)','recursive(10)','41','--max-steps=100','R_STEP_LIMIT')]:
 path=w/f'{case}.my';path.write_text(base.replace('HELPER',helper).replace('RHS',rhs).replace('INITIAL',initial))
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   binary=w/f'{case}-{mode}-{backend}';cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(path),'-o',str(binary),'--cache-dir',str(w/'trap-cache'),f'--backend={backend}','--mode=Debug']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   d=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(case=case,mode=mode,backend=backend,build_command=cmd,build_exit=d.returncode,build_stderr=d.stderr);r['runs'].append(row);save();assert d.returncode==0,row
   manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());row['manifest']=manifest;assert manifest['backend']==backend
   e=dict(env);e['MYLANG_MEMORY_LIMIT']='1M' if case=='budget' else '128M';e['MYLANG_OPTIONS']=' '.join(x for x in ('--gc-stress' if mode=='gc' else '',options) if x)
   d=subprocess.run([str(binary)],env=e,text=True,capture_output=True,timeout=30);row.update(exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),environment={k:v for k,v in e.items() if k.startswith('MYLANG_')});save();assert d.returncode==1 and d.stdout=='before\n' and trap in d.stderr,row
   if mode=='rc':
    c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in d.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   save();print(case,mode,backend,'pass',row.get('counts',{}),flush=True)
