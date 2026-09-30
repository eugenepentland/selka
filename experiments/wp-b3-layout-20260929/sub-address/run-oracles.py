import argparse, hashlib, json, os, pathlib, subprocess
p=argparse.ArgumentParser(); p.add_argument('--qbe',required=True); p.add_argument('--out',required=True); a=p.parse_args()
root=pathlib.Path.cwd(); out=root/a.out;out.mkdir(parents=True,exist_ok=True)
qbe=pathlib.Path(a.qbe).resolve();env=os.environ.copy();rows=[]
def run(cmd,name):
 r=subprocess.run(cmd,capture_output=True,text=True,env=env)
 (out/(name+'.stdout')).write_text(r.stdout);(out/(name+'.stderr')).write_text(r.stderr)
 rows.append({'command':cmd,'status':r.returncode})
 if r.returncode:raise RuntimeError((name,r.returncode,r.stderr))
 return r.stdout
for fixture in ['qbe-sub-address','qbe-zero-branch']:
 asm=out/(fixture+'.s');exe=out/(fixture+'.probe')
 run([str(qbe),'-o',str(asm),str(root/'tests/fixtures'/fixture/'probe.ssa')],fixture+'-qbe')
 run(['zig','cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-unused-command-line-argument','-UNDEBUG','-fsanitize=undefined',str(root/'tests/fixtures'/fixture/'probe.c'),str(asm),'-o',str(exe)],fixture+'-link')
 print(run([str(exe)],fixture+'-run').strip(),flush=True)
(out/'receipt.json').write_text(json.dumps({'qbe':str(qbe),'qbe_sha256':hashlib.sha256(qbe.read_bytes()).hexdigest(),'rows':rows},indent=2)+'\n')
