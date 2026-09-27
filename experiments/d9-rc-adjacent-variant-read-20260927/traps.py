from pathlib import Path
import os,json,subprocess,hashlib,sys
root=Path.cwd();w=root/'.tmp-variant-read'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
source='''record Payload:
    left: list[int]
    right: list[int]
union Item:
    empty,
    value: Payload
record Pool:
    items: list[Item]
def selected(pool: Pool, at: int) -> Payload:
    match pool.items[at]:
        case Item.value(payload):
            return payload
        case _:
            return Payload([], [])
def main(out: Stream) -> int:
    values = [3]
    pool = Pool([Item.value(Payload(values, values))])
    out.print("before")
    result = selected(pool, INDEX)
    pool.items.clear()
    out.print(result.left[0] + result.right[0])
    return 0
'''
r=json.loads((w/'traps.json').read_text()) if '--resume' in sys.argv else {'runs':[]};r['runs']=[x for x in r['runs'] if len(x.get('runs',[]))==180];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save():(w/'traps.json').write_text(json.dumps(r,indent=2)+'\n')
for case,index in [('steps','0'),('bounds','1')]:
 path=w/f'trap-{case}.my';path.write_text(source.replace('INDEX',index))
 if case=='steps' and len([x for x in r['runs'] if x['case']=='steps'])==8:continue
 for arm,compiler in [('before',root.parent/'d9-rc-integration/.tmp-rc/install-snapshot-joined/bin/mylang'),('after',w/'install/bin/mylang')]:
  for backend in ('qbe','llvm'):
   for mode in ('gc','rc'):
    binary=w/f'trap-{case}-{arm}-{mode}-{backend}';cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(path),'-o',str(binary),'--cache-dir',str(w/'trap-cache'),f'--backend={backend}','--mode=Debug']
    if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
    if mode=='rc':cmd+=['--rc-runtime=stats']
    d=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(case=case,arm=arm,mode=mode,backend=backend,compiler_sha256=sha(compiler),build_command=cmd,build_exit=d.returncode,build_stderr=d.stderr,runs=[]);r['runs'].append(row);save();assert d.returncode==0,row
    manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());row['manifest']=manifest;assert manifest['backend']==backend;row['binary_sha256']=sha(binary)
    for budget in (range(1,181) if case=='steps' else [0]):
     e=env|{'MYLANG_OPTIONS':(' --gc-stress' if mode=='gc' else '')+(f' --max-steps={budget}' if budget else '')}
     d=subprocess.run([str(binary)],env=e,text=True,capture_output=True,timeout=10);run=dict(budget=budget,exit=d.returncode,stdout=d.stdout,stderr=d.stderr,environment={k:v for k,v in e.items() if k.startswith('MYLANG_')});row['runs'].append(run)
     if case=='bounds':assert d.returncode==1 and 'R_LIST_BOUNDS' in d.stderr and d.stdout=='before\n',run
     else:assert (d.returncode==1 and 'R_STEP_LIMIT' in d.stderr) or (d.returncode==0 and d.stdout=='before\n6\n'),run
     if mode=='rc':
      c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in d.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')));run['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],run
     save()
    print('PASS',case,arm,mode,backend,flush=True)
for case in ('steps','bounds'):
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   rows=[x for x in r['runs'] if (x['case'],x['backend'],x['mode'])==(case,backend,mode)]
   assert [[(z['budget'],z['exit'],z['stdout']) for z in x['runs']] for x in rows][0]==[[(z['budget'],z['exit'],z['stdout']) for z in x['runs']] for x in rows][1]
print('MATCHED ALL TRAP BOUNDARIES',flush=True)
