import subprocess,json,pathlib,hashlib
p=pathlib.Path(__file__).resolve().parent; root=p.parents[1]; r={}
for arm in ('publish-joined','arena-origin'):
 c=root/'.tmp-rc/profile'/('install-'+arm)/'bin/mylang'
 for backend in ('qbe','llvm'):
  for source in ('grow','stash','driver'):
   if source=='driver' and arm=='publish-joined':continue
   src=root/'tests/lang/rc_arena_values.my' if source=='driver' else p/(source+'.my')
   out=p/(arm+'-'+backend+'-'+source)
   cmd=[str(c),'build',str(src),'-o',str(out),'--rc-runtime=stats','--keep-symbols']
   if backend=='llvm':cmd+=['--release']
   d=subprocess.run(cmd,text=True,capture_output=True);assert d.returncode==0,d.stderr
   d=subprocess.run([str(out)],text=True,capture_output=True)
   counts=next((json.loads(l.split(' ',1)[1]) for l in d.stderr.splitlines() if l.startswith('MYLANG_RC_COUNTS ')),None)
   key=arm+'/'+backend+'/'+source
   r[key]={'command':cmd,'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'binary_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'exit':d.returncode,'stdout':d.stdout,'stderr':d.stderr,'counts':counts}
   (p/'probe.json').write_text(json.dumps(r,indent=2)+'\n');print(key,d.returncode,counts,flush=True)
   expected=1 if arm=='publish-joined' else {'grow':12,'stash':4,'driver':0}[source]
   assert d.returncode==expected
   assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release']
