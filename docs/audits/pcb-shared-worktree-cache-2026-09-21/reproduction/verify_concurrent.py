from pathlib import Path
import json, os, subprocess, time
root=Path('/tmp/pcb-shared-cache-20260921'); evidence=root/'evidence';a=root/'dependency A';b=root/'dependency B'
env=dict(os.environ)
for key in ('MYLANG','CACHE','PCB_SHARED_CACHE'):env.pop(key,None)
for tree in (a,b):
    p=tree/'guest/main.my';p.write_text(p.read_text()+'\n# equal concurrent cold test requests\n')
start=time.monotonic()
procs=[subprocess.Popen(['guest/gate.sh','--focus','main'],cwd=tree,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for tree in (a,b)]
reports=[]
for i,p in enumerate(procs):
    out,err=p.communicate(timeout=60)
    (evidence/f'concurrent-gate-{i}.stdout').write_text(out);(evidence/f'concurrent-gate-{i}.stderr').write_text(err)
    assert p.returncode==0,err
    reports.append(json.loads(out))
assert sorted((r['passed'],r['cached'],r['executed']) for r in reports)==[(0,1,0),(1,0,1)],reports
(evidence/'concurrent-gates.json').write_text(json.dumps({'seconds':time.monotonic()-start,'reports':reports},indent=2)+'\n')
print('concurrent real cold test: one execution, one cache hit; PASS')
