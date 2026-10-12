import pathlib,subprocess,json,hashlib,os
root=pathlib.Path.cwd()
base=root/'.tmp/micro-gaps/words'
compiler=base/'install/bin/mylang'
source=root/'experiments/micro-gaps-20261012/words/text.my'
entries=[]
for counted in (False,True):
    binary=base/('text-counted' if counted else 'text-runtime')
    cmd=[str(compiler),'build',str(source),'-o',str(binary),'--release','--experimental-zero-rc','--link',str(root/'benchmarks/runtime/ports/native_clock.c'),'--cache-dir',str(base/'guest-cache')]
    if counted:cmd+=['--counters']
    ran=subprocess.run(cmd,capture_output=True,text=True)
    (base/('build-text-counted.log' if counted else 'build-text-runtime.log')).write_text(ran.stdout+ran.stderr)
    entries.append(dict(command=cmd,status=ran.returncode,binary=str(binary),sha256=hashlib.sha256(binary.read_bytes()).hexdigest() if ran.returncode==0 else None))
    if ran.returncode: print(ran.stdout+ran.stderr);break
out=root/'experiments/micro-gaps-20261012/words/build-manifest.json'
out.write_text(json.dumps(dict(compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),entries=entries),indent=2)+'\n')
raise SystemExit(0 if len(entries)==2 and all(x['status']==0 for x in entries) else 1)
