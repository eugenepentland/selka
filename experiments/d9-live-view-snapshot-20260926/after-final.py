import pathlib,subprocess,json,os,hashlib
r=pathlib.Path.cwd();d=r/'.tmp-rc/view-snapshot';c=r/'.tmp-rc/install-view-snapshot-final/bin/mylang';results=[]
for backend in ['qbe','llvm']:
 for mode in ['gc','rc']:
  cmd=['scripts/build-slot.sh','build',str(c),'build',str(d/'histories.my'),'--backend',backend,'--mode','ReleaseFast','--cache-dir',str(d/'after-cache'),'--run']+(['--gc-stress'] if mode=='gc' else ['--rc-runtime=stats'])+(['--llvm-opt','3','--lto'] if backend=='llvm' else [])
  x=subprocess.run(cmd,env=os.environ|{'TMPDIR':str(r/'.tmp-rc/tmp')},capture_output=True,text=True,timeout=300)
  results.append(dict(compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),source_sha256=hashlib.sha256((d/'histories.my').read_bytes()).hexdigest(),backend=backend,mode=mode,cmd=cmd,status=x.returncode,stdout=x.stdout,stderr=x.stderr));(d/'after-final.json').write_text(json.dumps(results,indent=2));print(backend,mode,x.returncode,repr(x.stdout),flush=True)
