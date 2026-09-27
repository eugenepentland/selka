from pathlib import Path
import hashlib,importlib.util,json,os,subprocess
R=Path.cwd();W=R/'.tmp-managed-readonly';P=R.parent/'d9-rc-performance'
spec=importlib.util.spec_from_file_location('core',P/'experiments/d9-rc-ownership-joined-20260927/measurement_core.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)
os.environ['TMPDIR']=str(W/'tmp');os.environ['ZIG_LOCAL_CACHE_DIR']=str(W/'guest-zig-cache')
C={'before':W/'install-before/bin/mylang','after':W/'install-draft/bin/mylang'}
D={'compiler_sha256':{s:M.A.sha(c) for s,c in C.items()},'emissions':[],'changed':{}}
def save():(W/'emit-audit.json').write_text(json.dumps(D,indent=2)+'\n')
for kind in ('schematic','lox'):
 p=next(p for p in M.A.programs() if p['kind']==kind);manifests={}
 for side,c in C.items():
  command,cwd=M.PC.emit_command(p,str(c));command=[str(R/'scripts/build-slot.sh'),'build',*command,'--rc-runtime']
  done=subprocess.run(command,cwd=cwd,env=M.PC.clean_env(),text=True,capture_output=True,timeout=600)
  row={'side':side,'kind':kind,'command':command,'status':done.returncode,'stderr':done.stderr}
  D['emissions'].append(row);save();assert done.returncode==0,row
  path=W/(kind+'-'+side+'-emitted.json');path.write_text(done.stdout)
  row.update(path=str(path),sha256=M.A.sha(path));save()
  manifests[side]={f['symbol']:f for f in json.loads(done.stdout)['functions']}
  print('emitted',kind,side,len(manifests[side]),flush=True)
 assert manifests['before'].keys()==manifests['after'].keys()
 changed=[]
 for symbol,a in manifests['before'].items():
  b=manifests['after'][symbol]
  if a['il']==b['il']:continue
  changed.append({'name':a['name'],'symbol':symbol,'before_il_sha256':hashlib.sha256(a['il'].encode()).hexdigest(),
                  'after_il_sha256':hashlib.sha256(b['il'].encode()).hexdigest(),
                  'calls':{key:{s:f['il'].count(key) for s,f in [('before',a),('after',b)]}
                           for key in ('call $myl_rc_native_loan','call $myl_rc_native_retain','call $myl_qbe_rc_frame_enter')}})
 D['changed'][kind]=changed;save();print('changed',kind,[f['name'] for f in changed],flush=True)
D['complete']=True;save()
