from pathlib import Path
import os,json,subprocess,hashlib
root=Path.cwd();w=root/'.tmp-schematic-audit';compiler=w/'install-final/bin/mylang';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'trap-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save():(w/'traps.json').write_text(json.dumps(r,indent=2)+'\n')
source='''record Row:
    label: bytes
    number: int
def selected(rows: list[Row], at: int, output: mut list[int]) -> int:
    value = rows[at].number
    output.append(value)
    return value
def main(out: Stream) -> int:
    with arena():
        rows = [Row(b"a" + bytes([49]), 7)]
        output: list[int] = []
        out.print("before")
        return selected(rows, INDEX, mut output)
'''
for index in (4,-3):
 path=w/f'bounds-{index}.my';path.write_text(source.replace('INDEX',str(index)))
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   binary=w/f'bounds-{index}-{mode}-{backend}';cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(path),'-o',str(binary),'--cache-dir',str(w/'trap-cache'),f'--backend={backend}']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   d=subprocess.run(cmd,env=env,text=True,capture_output=True);row={'index':index,'backend':backend,'mode':mode,'build_command':cmd,'build_exit':d.returncode,'build_stderr':d.stderr};r['runs'].append(row);save();assert d.returncode==0,row
   e=dict(env)
   if mode=='gc':e['MYLANG_OPTIONS']='--gc-stress'
   d=subprocess.run([str(binary)],env=e,text=True,capture_output=True,timeout=20);row.update(exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());save();assert d.returncode==1 and d.stdout=='before\n' and 'R_LIST_BOUNDS' in d.stderr,row
   if mode=='rc':
    c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in d.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   save();print(index,mode,backend,'pass',row.get('counts',{}),flush=True)
