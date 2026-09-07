from pathlib import Path
import subprocess,json,hashlib
root=Path(__file__).parent.resolve();compiler=Path('/home/epentland/ai/canopy/mylang-stdlib-collections/zig-out/bin/mylang');zig='/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'
def run(argv):
 p=subprocess.run([str(x) for x in argv],capture_output=True,timeout=90);assert p.returncode==0,(argv,p.stderr.decode()[:1000]);return p.stdout
source=root/'mutations.my';results=[]
for memory in ['general','arena']:
 output=run([compiler,'run',source,'--memory='+memory]);assert output==b'42\n';results.append(['VM',memory,output.decode().strip()])
c=root/'mutations.c';c.write_bytes(run([compiler,'emit-c',source]));
for mode in ['-O0','-O2']:
 binary=root/'mutations';run([zig,'cc','-std=c11',mode,'-fsanitize=undefined','-fno-sanitize-recover=undefined',c,'-o',binary]);output=run([binary]);assert output==b'42\n';results.append(['native',mode,output.decode().strip()])
receipt=dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),cases=results);(root/'runtime-results.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt))
