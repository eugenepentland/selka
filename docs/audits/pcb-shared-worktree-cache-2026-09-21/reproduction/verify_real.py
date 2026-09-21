from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import time

root = Path('/tmp/pcb-shared-cache-20260921')
stage = root/'stage'
evidence = root/'evidence'
repo = root/'real-repo'
repo.mkdir()
for name in ('guest','tools'):
    shutil.copytree(stage/name, repo/name, ignore=shutil.ignore_patterns('.*','__pycache__'))
shutil.copy2(stage/'workbench.json', repo/'workbench.json')
(repo/'.gitignore').write_text('.workbench/\n.mylang/\n.pcb-workbench/\n')
env = dict(os.environ)
for key in ('MYLANG','CACHE','PCB_SHARED_CACHE'):
    env.pop(key, None)
def git(*args):
    subprocess.run(['git','-C',str(repo),*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
git('init','-q');git('add','.');git('-c','user.name=Cache verification','-c','user.email=cache-test@local.invalid','-c','core.hooksPath=/dev/null','commit','-qm','private worktree fixture')
a=root/'real worktree A';b=root/'real worktree B'
for tree in (a,b):git('worktree','add','--detach',str(tree),'HEAD')
records=[]
def run(label,tree,command,extra=None):
    start=time.monotonic()
    result=subprocess.run(command,cwd=tree,env=env| (extra or {}),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    (evidence/(label+'.stdout')).write_text(result.stdout)
    (evidence/(label+'.stderr')).write_text(result.stderr)
    rec={'label':label,'seconds':time.monotonic()-start,'exit':result.returncode,'cwd':str(tree),'command':command}
    records.append(rec)
    (evidence/'real-worktrees.json').write_text(json.dumps(records,indent=2)+'\n')
    print(json.dumps(rec),flush=True)
    assert result.returncode==0,result.stderr[-3000:]
    return result
first=run('real-build-a',a,['guest/build-app.sh'])
second=run('real-build-b',b,['guest/build-app.sh'],{'PCB_BUILD_JOBS':'3'})
assert first.stdout==second.stdout
assert 'reused' in first.stderr and 'reused' in second.stderr
old=Path('/home/epentland/ai/canopy/pcb-workbench/.workbench/builds/2b2f95f37f22ee93f24a3efd87392ba49c7886136e62530c08955c0c39a60068/pcb-workbench')
assert hashlib.sha256(Path(first.stdout.strip()).read_bytes()).digest()==hashlib.sha256(old.read_bytes()).digest()
run('real-help-b',b,['guest/pcb.sh','help','--journal',str(b/'journal')])
first=run('real-gate-a',a,['guest/gate.sh'])
second=run('real-gate-b',b,['guest/gate.sh'])
for result in (first,second):
    data=json.loads(result.stdout)
    assert data['failed']==0 and data['passed']+data['cached']==400,data
assert json.loads(second.stdout)['cached']==400
assert json.loads(second.stdout)['executed']==0
print('real PCB worktrees: PASS',flush=True)
