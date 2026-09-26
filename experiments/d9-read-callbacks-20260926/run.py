import pathlib,subprocess,os,json,hashlib
r=pathlib.Path.cwd();w=r/'.tmp/rc-read-captures';c=w/'install/bin/mylang';src=r/'tests/lang/collection_read_callbacks.my';rows=[]
for mode in ['gc','rc']:
 for backend in ['qbe','llvm']:
  binary=w/(mode+'-'+backend);cmd=['scripts/build-slot.sh','build',str(c),'build',str(src),'--backend',backend,'--mode','ReleaseFast','--cache-dir='+str(w/'cache'),'-o',str(binary)]
  if mode=='rc':cmd+=['--rc-runtime=stats']
  if backend=='qbe':cmd+=['--qbe='+str(c.parent/'qbe')]
  else:cmd+=['--llvm-opt','3','--lto']
  b=subprocess.run(cmd,capture_output=True,text=True);row=dict(mode=mode,backend=backend,command=cmd,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),build_exit=b.returncode,build_log=b.stdout+b.stderr)
  if b.returncode==0:
   x=subprocess.run([str(binary)],capture_output=True,text=True,env={**os.environ,'MYLANG_OPTIONS':'--gc-stress'});row.update(exit=x.returncode,stdout=x.stdout,stderr=x.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());row['passed']=x.returncode==0
   if mode=='rc':
    counts=[json.loads(line.split(' ',1)[1]) for line in x.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    row['counts']=counts
    row['passed']=row['passed'] and len(counts)==1 and counts[0]['heap_allocate']==counts[0]['retire'] and counts[0]['owner_acquire']+counts[0]['heap_allocate']==counts[0]['owner_release'] and counts[0]['hold_acquire']==counts[0]['hold_release']
  else:row['passed']=False
  rows.append(row);print(row,flush=True);(w/'validation.json').write_text(json.dumps(rows,indent=2))
  if not row['passed']:raise SystemExit(1)
