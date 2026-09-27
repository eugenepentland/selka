from pathlib import Path
import hashlib,json,os,subprocess
R=Path.cwd();W=R/'.tmp-managed-readonly/cache-control';W.mkdir(exist_ok=True)
C=R/'.tmp-managed-readonly/install-bytes/bin/mylang';S=W/'main.my'
E={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
E.update(TMPDIR=str(R/'.tmp-managed-readonly/tmp'),ZIG_LOCAL_CACHE_DIR=str(R/'.tmp-managed-readonly/guest-zig-cache'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
D={'compiler_sha256':sha(C),'driver_sha256':sha(__file__),'emissions':[],'builds':[],'runs':[]}
def save():(W/'results.json').write_text(json.dumps(D,indent=2)+'\n')
prefix='''record Item:
    text: bytes
    number: int
def leaf(items: list[Item], index: int) -> Item:
'''
suffix='''def middle(items: list[Item], index: int) -> int:
    saved = leaf(items, index)
    return saved.number + int(saved.text[0])
def selected(items: list[Item]) -> int:
    return middle(items, 0)
def main() -> int:
    return selected([Item(b"a", 3)])
'''
def execute(cmd):
 p=subprocess.run(list(map(str,cmd)),env=E,text=True,capture_output=True,timeout=600)
 return {'command':list(map(str,cmd)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def emit(label,cache):
 row=execute([R/'scripts/build-slot.sh','build',C,'emit-qbe',S,'--rc-runtime','--cache-dir='+str(cache)])
 assert row['status']==0,row
 path=W/(label+'.json');path.write_text(row.pop('stdout'))
 row.update(label=label,manifest=str(path),manifest_sha256=sha(path),source_sha256=sha(S))
 D['emissions'].append(row);save()
 return {f['name']:f['il'] for f in json.loads(path.read_text())['functions']}
states=[('plain','    return items[index]\n'),('changed','    return items[index + 0]\n'),
        ('allocated','    fresh = [items[index]]\n    return fresh[0]\n')]
for label,body in states:
 S.write_text(prefix+body+suffix)
 (W/(label+'.my')).write_text(S.read_text())
 warm=emit(label+'-warm',W/'warm-cache')
 cold=emit(label+'-cold',W/(label+'-cold-cache'))
 assert warm==cold,(label,'warm and cold emission differ')
 assert ('call $myl_qbe_rc_frame_enter' in warm['selected'])==(label=='allocated')
 assert ('call $myl_qbe_rc_frame_enter' in warm['middle'])==(label=='allocated')
 print('emission',label,'warm/cold identical',flush=True)
for backend in ('qbe','llvm'):
 for state in ('warm','cold'):
  binary=W/(backend+'-'+state)
  cmd=[R/'scripts/build-slot.sh','build',C,'build',S,'--rc-runtime=stats','--mode=ReleaseFast',
       '--backend='+backend,'--cache-dir='+str(W/('warm-cache' if state=='warm' else 'native-cold-'+backend)),'-o',binary]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  row=execute(cmd);D['builds'].append(row);save();assert row['status']==0,row
  row['binary_sha256']=sha(binary);row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());save()
  row=execute([binary]);row.update(backend=backend,cache=state);D['runs'].append(row);save();assert row['status']==100,row
  counts=[json.loads(s.split(' ',1)[1]) for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
  assert len(counts)==1,row
  n=counts[0];row['counts']=n
  assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],row
  print('native',backend,state,'status100 balanced',flush=True)
D['complete']=True;save()
