from pathlib import Path
import os,json,subprocess,hashlib,time,statistics
root=Path.cwd();work=root/'.tmp-mut-argument/type-facts';before=root/'.tmp-mut-argument/lox-post-record/current';after=work/'measure';peer=root.parent/'d9-rc-lox-probe-astra';script=root.parent/'d9-rc-performance/.tmp-rc-performance/lox-scripts/binary_trees.tree.lox';expected=(peer/'experiments/d9-rc-plain-record-write-20260927/expected-n10.txt').read_text();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(work),MYLANG_MEMORY_LIMIT='8G')
r={'input':str(script),'input_sha256':sha(script),'source_base':'5b87601297f01810968b9f7ac554c484d5848cca','production_patch_sha256':sha(work/'source.patch'),'accepted_gc_medians':{'qbe':7243227886,'llvm':3433157037},'cpu':2,'runs':[]}
def save():(work/'lox-results.json').write_text(json.dumps(r,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for counted in (False,True):
  for repeat in range(1 if counted else 3):
   for side in (('before','after') if repeat%2==0 else ('after','before')):
    directory=before if side=='before' else after;binary=directory/(backend+('-stats' if counted else '-production'));manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
    if backend=='llvm':assert manifest['optimization']=='3' and manifest['lto'] and not manifest['thin_lto']
    cmd=['taskset','-c','2']+([] if counted else ['perf','stat','-x,','-e','cpu_core/instructions/u','--'])+[str(binary),'--engine=vm',str(script)];print('START',backend,side,counted,repeat,flush=True);start=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=180);row={'backend':backend,'side':side,'counted':counted,'repeat':repeat,'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':time.monotonic()-start,'binary_sha256':sha(binary)};r['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row
    if counted:
     c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'];row['counts']=c
    else:
     fields=next(x.split(',') for x in p.stderr.splitlines() if ',cpu_core/instructions/u,' in x);row['instructions']=int(fields[0]);row['event_running_percent']=float(fields[4]);assert row['event_running_percent']==100
    save();print('DONE',backend,side,counted,repeat,round(row['seconds'],2),row.get('instructions',row.get('counts')),flush=True)
 rows=[x for x in r['runs'] if x['backend']==backend];a,b=[x['counts'] for x in rows if x['counted']];assert a==b
 med={side:statistics.median(x['instructions'] for x in rows if not x['counted'] and x['side']==side) for side in ('before','after')};r.setdefault('medians',{})[backend]={**med,'after_over_before':med['after']/med['before'],'before_over_gc':med['before']/r['accepted_gc_medians'][backend],'after_over_gc':med['after']/r['accepted_gc_medians'][backend]};save();print('MEDIAN',backend,r['medians'][backend],flush=True)
