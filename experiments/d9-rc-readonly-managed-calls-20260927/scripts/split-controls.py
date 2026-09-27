from pathlib import Path
import json,os,subprocess,hashlib
R=Path.cwd();W=R/'.tmp-managed-readonly';C={'before':W/'install-before/bin/mylang','after':W/'install-bytes/bin/mylang'}
E={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};E.update(TMPDIR=str(W/'tmp'),ZIG_LOCAL_CACHE_DIR=str(W/'guest-zig-cache'))
D={'builds':[],'runs':[]};sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save():(W/'split-controls.json').write_text(json.dumps(D,indent=2)+'\n')
source=(R/'tests/lang/rc_readonly_managed_calls.my').read_text().split('def main(')[0]
for case,test in [('large','test_large_indirect_results_keep_saved_bits_after_calls'),('small','test_saved_small_results_survive_calls_and_loop_reuse')]:
 path=W/(case+'-only.my');path.write_text(source+f'def main(out: Stream) -> int:\n    out.print({test}())\n    return 0\n')
 for side,c in C.items():
  binary=W/'bin'/(case+'-only-'+side+'-llvm')
  cmd=[R/'scripts/build-slot.sh','build',c,'build',path,'--mode=ReleaseFast','--backend=llvm','--llvm-opt=3','--lto','--rc-runtime=stats','--cache-dir='+str(W/('cache-split-'+side)),'-o',binary]
  p=subprocess.run(list(map(str,cmd)),env=E,text=True,capture_output=True,timeout=600)
  row={'case':case,'side':side,'command':list(map(str,cmd)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'source_sha256':sha(path),'compiler_sha256':sha(c)};D['builds'].append(row);save();print('build',case,side,p.returncode,flush=True)
  if p.returncode:continue
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']=='llvm';row.update(binary_sha256=sha(binary),manifest=manifest);save()
  p=subprocess.run([str(binary)],env=E,text=True,capture_output=True,timeout=60)
  counts=[json.loads(s.split(' ',1)[1]) for s in p.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')];row={'case':case,'side':side,'command':[str(binary)],'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'counts':counts};D['runs'].append(row);save()
  assert p.returncode==0 and p.stdout=='True\n' and len(counts)==1,row
  n=counts[0];assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],row
D['complete']=True;save()
