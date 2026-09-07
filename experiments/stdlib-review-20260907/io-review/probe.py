from pathlib import Path
import subprocess,os,json,hashlib
root=Path('/home/epentland/ai/canopy/mylang');temp=Path(__file__).parent.resolve();compiler=root/'zig-out/bin/mylang';zig='/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'
def run(argv,env=None):
 p=subprocess.run([str(x) for x in argv],capture_output=True,timeout=90,env=env);assert p.returncode==0,(argv,p.stderr.decode()[:1500]);return p
c=temp/'guest.c';c.write_bytes(run([compiler,'emit-project-c',temp/'main.my']).stdout)
provider=temp/'provider.c';source=(root/'tests/standard_io_provider.c').read_text();source=source.replace('(void)unused; (void)permissions;', '(void)unused; if (permissions != 6) abort();');provider.write_text(source)
results=[]
for mode in ['-O0','-O2']:
 binary=temp/'guest';run([zig,'cc','-std=c11',mode,'-fsanitize=address,undefined','-fno-sanitize-recover=undefined','-DMYLANG_NATIVE_PROVIDER=1','-I',root/'src',c,provider,'-o',binary]);env=os.environ.copy();env['IO_WRITE_FAIL']='2';env.pop('IO_STALL',None);p=run([binary],env);assert p.stdout==b'42\n',p;expected=b'0123456789'*6+b'ABCDEFGH';assert b'output: '+expected+b'\n' in p.stderr,p.stderr;assert b'io-live: 0 acquired: 1 released: 1' in p.stderr;results.append(dict(mode=mode,stdout=p.stdout.decode(),stderr=p.stderr.decode()))
(temp/'result.json').write_text(json.dumps(dict(compiler_sha=hashlib.sha256(compiler.read_bytes()).hexdigest(),results=results),indent=2)+'\n');print(json.dumps(results))
