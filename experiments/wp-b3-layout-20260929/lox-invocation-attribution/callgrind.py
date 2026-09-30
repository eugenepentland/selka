import hashlib,json,os,subprocess,time
from pathlib import Path
work=Path(__file__).resolve().parent;own=work.parents[1];tools=work/'valgrind-local/usr'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(own/'.tmp'),MYLANG_MEMORY_LIMIT='8G',VALGRIND_LIB=str(tools/'libexec/valgrind'))
receipt={'tool':subprocess.check_output([str(tools/'bin/valgrind'),'--version'],env=env).decode().strip(),'tool_package_sha256':hashlib.sha256((work/'valgrind-package.deb').read_bytes()).hexdigest(),'cpu':0,'measurement':'Exact simulated instruction/basic-block attribution on allocated-section-identical symbol counterparts; not quantitative acceptance or a timing sample.','sides':{}}
for side in ['control','candidate']:
    dest=work/side
    cmd=[str(own/'scripts/build-slot.sh'),'build','taskset','-c','0',str(tools/'bin/valgrind'),'--tool=callgrind','--dump-instr=yes','--collect-jumps=yes','--compress-pos=no','--compress-strings=no','--callgrind-out-file='+str(dest/'callgrind.out'),str(dest/'lox.symbols'),'--engine=vm',str(work/'invocation.n30000.lox')]
    print(side,'Callgrind',flush=True);start=time.monotonic();done=subprocess.run(cmd,cwd=work,env=env,capture_output=True)
    (dest/'callgrind.stdout').write_bytes(done.stdout);(dest/'callgrind.stderr').write_bytes(done.stderr)
    receipt['sides'][side]={'command':cmd,'status':done.returncode,'elapsed_seconds':time.monotonic()-start,'stdout':done.stdout.decode(errors='replace'),'stderr':done.stderr.decode(errors='replace')}
    (work/'callgrind-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    assert done.returncode==0 and done.stdout==b'30000\n',done.stderr.decode(errors='replace')
    annotate=subprocess.run([str(tools/'bin/callgrind_annotate'),'--show=Ir','--threshold=100','--auto=no',str(dest/'callgrind.out')],cwd=work,env=env,capture_output=True)
    (dest/'callgrind.annotate').write_bytes(annotate.stdout);assert annotate.returncode==0
print('both passed',flush=True)
