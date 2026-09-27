import hashlib,json,pathlib,subprocess
r=pathlib.Path.cwd();w=r/'.tmp-rc/empty-frame';c=r/'.tmp-rc/install-empty-frame/bin/mylang'
result={'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'runs':[]}
for backend in ['qbe','llvm']:
 for mode in ['rc','gc']:
  for name in ['rc_empty_frames','rc_inert_receivers','rc_read_loans','iteration_identity','field_augmented','array_places','rc_semantic_history','rc_plain_aggregates','rc_scalar_replacements']:
   cmd=[str(c),'test',str(r/'tests/lang'/f'{name}.my'),'--force','--json','--jobs','2','--cache-dir='+str(w/'test-cache')]
   cmd+=['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress']
   if backend=='llvm':cmd+=['--release']
   p=subprocess.run(cmd,text=True,capture_output=True);row=dict(backend=backend,mode=mode,name=name,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);result['runs'].append(row);(w/'checks.json').write_text(json.dumps(result,indent=2)+'\n')
   assert p.returncode==0,row
   a=json.loads(p.stdout);assert a['failed']==0;print(backend,mode,name,a['passed'],flush=True)
  cmd=[str(c),'run',str(w/'bounds.my'),'--cache-dir='+str(w/'test-cache')]
  cmd+=['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress']
  if backend=='llvm':cmd+=['--release']
  p=subprocess.run(cmd,text=True,capture_output=True);row=dict(backend=backend,mode=mode,name='bounds',command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);result['runs'].append(row);(w/'checks.json').write_text(json.dumps(result,indent=2)+'\n')
  assert p.returncode==1 and 'R_LIST_BOUNDS' in p.stderr,row
  print(backend,mode,'bounds PASS',flush=True)
