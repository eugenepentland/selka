from pathlib import Path
import hashlib,json,os,subprocess
R=Path.cwd();W=R/'.tmp-readonly';source=W/'traps-fixed.my'
C={'before':R.parent/'d9-rc-integration/.tmp-rc/install-ownership-joined-fixed/bin/mylang','after':W/'install-after/bin/mylang'}
E={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
E.update(TMPDIR=str(W/'tmp'),ZIG_LOCAL_CACHE_DIR=str(R/'.zig-cache-readonly-guests'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
D={'driver_sha256':sha(__file__),'builds':[],'runs':[]}
def save():(W/'traps-debug.json').write_text(json.dumps(D,indent=2)+'\n')
source.write_text('''record Item:
    text: bytes
    number: int
def leaf(items: list[Item], index: int) -> int:
    return items[index].number
def middle(items: list[Item], index: int) -> int:
    return leaf(items, index) + 1
def main(args: list[str]) -> int:
    index = 0
    if len(args) > 0:
        index = 1
    items = [Item(b"a", 9223372036854775807)]
    return middle(items, index)
''')
for side,c in C.items():
 for backend in ('qbe','llvm'):
  binary=W/'bin'/f'trap-debug-{side}-{backend}'
  cmd=[R/'scripts/build-slot.sh','build',c,'build',source,'--mode=Debug','--backend='+backend,
       '--rc-runtime=stats','--cache-dir='+str(W/('cache-traps-'+side)),'-o',binary]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  p=subprocess.run(list(map(str,cmd)),env=dict(E,MYLANG_OPTIONS='--max-steps=5000 --max-frames=128'),capture_output=True,text=True,timeout=600)
  row={'side':side,'backend':backend,'command':list(map(str,cmd)),'compiler_sha256':sha(c),'source_sha256':sha(source),
       'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'options':'--max-steps=5000 --max-frames=128'}
  D['builds'].append(row);save();assert p.returncode==0,row
  row['binary_sha256']=sha(binary);row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());save()
  for case,args,options,code in [('bounds',['bounds'],'','R_LIST_BOUNDS'),('overflow',[],'','R_OVERFLOW'),
                               ('steps',[],'--max-steps=22','R_STEP_LIMIT'),('frames',[],'--max-frames=2','R_FRAME_LIMIT')]:
   cmd=[str(binary),*args]
   p=subprocess.run(cmd,env=dict(E,MYLANG_OPTIONS=options),capture_output=True,text=True,timeout=60)
   row={'side':side,'backend':backend,'case':case,'command':cmd,'options':options,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'expected_trap':code}
   counts=[json.loads(s.split(' ',1)[1]) for s in p.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
   D['runs'].append(row);save();assert p.returncode==1 and code in p.stderr,row
   assert len(counts)==1,row
   n=counts[0];row['counts']=n
   assert n['hold_acquire']==n['hold_release'] and n['retire']==n['heap_allocate'] and n['owner_release']==n['owner_acquire']+n['heap_allocate'],row
   save();print('passed',side,backend,case,flush=True)
for backend in ('qbe','llvm'):
 for case in ('bounds','overflow','steps','frames'):
  pair=[r for r in D['runs'] if r['backend']==backend and r['case']==case]
  cleaned=['\n'.join(s for s in r['stderr'].splitlines() if not s.startswith('MYLANG_RC_COUNTS ')) for r in pair]
  assert len(pair)==2 and cleaned[0]==cleaned[1] and pair[0]['stdout']==pair[1]['stdout'],pair
D['complete']=True;save()
