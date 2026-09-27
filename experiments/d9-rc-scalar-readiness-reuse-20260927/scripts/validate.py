from pathlib import Path
import os,json,hashlib,subprocess,sys
root=Path.cwd();w=root/'.tmp-mut-argument/scalar-readiness-prototype';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env['TMPDIR']=str(w)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
compilers={'before':root.parent/'d9-rc-readiness-before-astra/.tmp-readiness/install/bin/mylang','after':w/'install/bin/mylang'}
d={'runs':[],'builds':[]};path=w/('validation-'+sys.argv[1]+'.json')
def save():path.write_text(json.dumps(d,indent=2)+'\n')
def run(cmd,timeout=600):return subprocess.run(list(map(str,cmd)),env=env,capture_output=True,text=True,timeout=timeout)
cmd=['cc','-O2','-DMYL_NATIVE_RC_COUNTING=1','-I',root/'src',w/'embedding.c','-ldl','-o',w/'embedding'];p=run(cmd);assert p.returncode==0,p.stderr
for side in sys.argv[1:]:
 c=compilers[side]
 for backend in ('qbe','llvm'):
  for source in (root/'tests/lang/rc_append_loops.my',root/'tests/lang/rc_plain_appends.my',w/'embed.my'):
   library=source.name=='embed.my';binary=w/(source.stem+'-'+side+'-'+backend+('.so' if library else ''))
   cmd=[root/'scripts/build-slot.sh','build',c,'build',source,'--rc-runtime=stats','--backend='+backend,'--mode='+('Debug' if library else 'ReleaseFast'),'-o',binary,'--cache-dir='+str(w/('cache-'+side))]
   if library:cmd+=['--library']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=run(cmd);row={'side':side,'backend':backend,'source':str(source),'source_sha256':sha(source),'compiler':str(c),'compiler_sha256':sha(c),'build':list(map(str,cmd)),'status':p.returncode,'stderr':p.stderr};d['builds'].append(row);save();assert p.returncode==0,row
   manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend;row.update(binary=str(binary),binary_sha256=sha(binary),manifest=manifest);save()
   functions={f['name']:f['symbol'] for f in manifest['functions']}
   for mode in (range(1,8) if library else (0,)):
    cmd=[w/'embedding',binary,functions['grow'],functions['heap_frame'],functions['written'],str(mode)] if library else [binary]
    p=run(cmd,60);r={'side':side,'backend':backend,'source':source.name,'mode':mode,'command':list(map(str,cmd)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(r);save();assert p.returncode==0,r
    counts=[json.loads(x.split(' ',1)[1]) for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1,r
    r['counts']=counts[0];n=counts[0];assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],r
    save();print(side,backend,source.name,mode,p.stdout.strip(),flush=True)
