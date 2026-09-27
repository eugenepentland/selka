import pathlib,subprocess,json,hashlib,os,resource
r=pathlib.Path.cwd();w=r/'.tmp-rc/empty-frame';compilers={'before':r.parent/'d9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang','after':r/'.tmp-rc/install-empty-frame/bin/mylang'}
data={'compilers':{k:{'path':str(v),'sha256':hashlib.sha256(v.read_bytes()).hexdigest()} for k,v in compilers.items()},'rows':[]}
def save():(w/'validation.json').write_text(json.dumps(data,indent=2)+'\n')
def balanced(p):
 lines=[line for line in p.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')];assert len(lines)==1,p.stderr
 c=json.loads(lines[0].split(' ',1)[1]);assert c['heap_allocate']==c['retire'] and c['owner_release']==c['heap_allocate']+c['owner_acquire'] and c['hold_acquire']==c['hold_release'],c
 return c
for backend in ['qbe','llvm']:
 for side,c in compilers.items():
  for case,src,fast,runs in [
   ('positive',r/'tests/lang/rc_empty_frames.my',False,[([], '',None)]),
   ('bounds',w/'bounds.my',False,[([], '', 'R_LIST_BOUNDS')]),
   ('overflow',w/'overflow.my',False,[([], '', 'R_OVERFLOW')]),
   ('steps',w/'steps.my',False,[([], '--max-steps=500','R_STEP_LIMIT')]),
   ('frames',w/'frames.my',False,[([], '--max-frames=16','R_FRAME_LIMIT')]),
   ('floor',w/'frames.my',True,[([], '', 'R_FRAME_LIMIT')]),
   ('heap',w/'heap.my',False,[([], '',None),(['fail'], '', 'R_LIST_BOUNDS')])]:
   binary=w/f'{side}-{backend}-{case}'
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(src),'-o',str(binary),'--rc-runtime=stats','--cache-dir='+str(w/f'cache-{side}'),'--keep-symbols','--backend',backend,'--mode','ReleaseFast' if fast else 'Debug']
   if backend=='llvm':cmd+=['--llvm-opt','3','--lto']
   p=subprocess.run(cmd,text=True,capture_output=True);row={'side':side,'backend':backend,'case':case,'build_command':cmd,'build_status':p.returncode,'build_stdout':p.stdout,'build_stderr':p.stderr};data['rows'].append(row);save();assert p.returncode==0,row
   row['binary_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest();row['runs']=[]
   for args,options,expected in runs:
    def smallstack():resource.setrlimit(resource.RLIMIT_STACK,(262144,262144))
    env=os.environ.copy();env['MYLANG_OPTIONS']=options
    p=subprocess.run([str(binary)]+args,text=True,capture_output=True,env=env,timeout=60,preexec_fn=smallstack if case=='floor' else None)
    run={'args':args,'options':options,'expected':expected,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};row['runs'].append(run);save()
    assert p.returncode==(1 if expected else 0),run
    if expected:assert expected in p.stderr,run
    run['counts']=balanced(p);save()
   print(backend,side,case,'PASS',flush=True)
# Before/after codes, outputs and all counters must agree, including trap cleanup.
for backend in ['qbe','llvm']:
 before={row['case']:row for row in data['rows'] if row['backend']==backend and row['side']=='before'}
 after={row['case']:row for row in data['rows'] if row['backend']==backend and row['side']=='after'}
 for key in before:
  for a,b in zip(before[key]['runs'],after[key]['runs']):
   assert (a['status'],a['stdout'])==(b['status'],b['stdout']),(key,a,b)
   # Physical stack frames may shrink under LLVM; unlike logical limits, the
   # number of activations before the native floor is not a fixed budget.
   ignored={'hold_acquire','hold_release'} if key=='floor' else set()
   assert {k:v for k,v in a['counts'].items() if k not in ignored}=={k:v for k,v in b['counts'].items() if k not in ignored},(key,a,b)
   trace=lambda run:'\n'.join(line for line in run['stderr'].splitlines() if not line.startswith('MYLANG_RC_COUNTS '))
   assert trace(a)==trace(b),(key,a,b)
print('all paired controls passed',flush=True)
