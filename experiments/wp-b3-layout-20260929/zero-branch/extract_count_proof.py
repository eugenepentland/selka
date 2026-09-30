from pathlib import Path
import json,re,subprocess
root=Path('.tmp/zero-probe')
compiler=str(Path('.tmp/zero/bin/mylang').resolve())
source=Path('experiments/wp-b3-layout-20260929/count-carry/probe/input.my')
r=subprocess.run([compiler,'emit-qbe',str(source),'--rc-runtime'],capture_output=True,text=True)
(root/'emit.stderr').write_text(r.stderr);assert r.returncode==0,r.stderr
(root/'manifest.json').write_text(r.stdout)
il=next(f['il'] for f in json.loads(r.stdout)['functions'] if f['name']=='keep')
fragments=[]
for name,offset in [('owner',32),('hold',24)]:
 pattern=r' %v\d+ =l sub (%v\d+), '+str(offset)+r'\n # myl-rc %v\d+\n %v\d+ =l loadl %v\d+\n %v\d+ =l add %v\d+, 1\n %v\d+ =w ceql %v\d+, 0\n jnz %v\d+, @rcglimit\d+, @rcgcapacity\d+\n@rcglimit\d+\n %v\d+ =w call \$myl_qbe_rc_status\(l %ctx, w 2\)\n jmp @failure\n@rcgcapacity\d+\n storel %v\d+, %v\d+\n'
 match=re.search(pattern,il);assert match,(name,offset)
 body=match[0].replace(match[1],'%payload')
 fragments.append('export function w $'+name+'(l %ctx, l %payload, l %output) {\n@start\n'+body+' storel %payload, %output\n ret 1\n@failure\n ret 0\n}\n')
(root/'count-probe.ssa').write_text('\n'.join(fragments))
with (root/'count-probe.s').open('w') as f:r=subprocess.run(['.tmp/zero/bin/qbe',str(root/'count-probe.ssa')],stdout=f,stderr=subprocess.PIPE,text=True)
assert r.returncode==0,r.stderr
r=subprocess.run(['cc','-std=c11','-DMYL_NATIVE_RC=1','-O2','-Wall','-Wextra','-Werror','-fsanitize=undefined','-fno-sanitize-recover=all','-I','src',str(root/'count-probe.c'),str(root/'count-probe.s'),'-o',str(root/'count-probe')],capture_output=True,text=True)
(root/'count-build.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
r=subprocess.run([str(root/'count-probe')],capture_output=True,text=True)
(root/'count-proof.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
print(r.stdout.strip())
