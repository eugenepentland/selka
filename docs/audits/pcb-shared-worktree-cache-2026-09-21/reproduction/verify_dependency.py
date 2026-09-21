from pathlib import Path
import json, os, shutil, subprocess, time
root=Path('/tmp/pcb-shared-cache-20260921'); evidence=root/'evidence'; stage=root/'stage'; repo=root/'dependency-repo'
repo.mkdir();(repo/'guest').mkdir()
shutil.copytree(stage/'tools',repo/'tools',ignore=shutil.ignore_patterns('__pycache__'))
for p in (stage/'guest').glob('*.sh'):shutil.copy2(p,repo/'guest'/p.name)
config=json.loads((stage/'workbench.json').read_text());config['project']='pcb-cache-dependency-verification-20260921'
(repo/'workbench.json').write_text(json.dumps(config)+'\n')
(repo/'guest/main.my').write_text('module main\nimport dependency\n\ndef main(out: Stream) -> int:\n    out.print(dependency.value())\n    return 0\n\npublic def test_value() -> bool:\n    return dependency.value() == 3\n')
original='module dependency\n\npublic def value() -> int:\n    return 3\n'
(repo/'guest/dependency.my').write_text(original)
(repo/'guest/test-inventory.txt').write_text('')
(repo/'.gitignore').write_text('.workbench/\n.mylang/\n')
def git(*a): subprocess.run(['git','-C',str(repo),*a],check=True,capture_output=True)
git('init','-q');git('add','.');git('-c','user.name=Cache verification','-c','user.email=cache-test@local.invalid','-c','core.hooksPath=/dev/null','commit','-qm','private dependency fixture')
a=root/'dependency A';b=root/'dependency B'
for tree in (a,b):git('worktree','add','--detach',str(tree),'HEAD')
env=dict(os.environ)
for key in ('MYLANG','CACHE','PCB_SHARED_CACHE'):env.pop(key,None)
records=[]
def run(label,tree,command,status=0):
    start=time.monotonic();p=subprocess.run(command,cwd=tree,env=env,capture_output=True,text=True)
    (evidence/(label+'.stdout')).write_text(p.stdout);(evidence/(label+'.stderr')).write_text(p.stderr)
    records.append({'label':label,'seconds':time.monotonic()-start,'exit':p.returncode,'command':command})
    (evidence/'dependency-worktrees.json').write_text(json.dumps(records,indent=2)+'\n')
    assert p.returncode==status,(label,p.returncode,p.stderr[-3000:])
    print(label,records[-1]['seconds'],flush=True)
    return p
first=run('dep-build-a',a,['guest/build-app.sh']).stdout.strip()
second=run('dep-build-b',b,['guest/build-app.sh']).stdout.strip()
assert first==second
assert run('dep-run-a',a,[first]).stdout.strip()=='3'
test_a=run('dep-test-a',a,['guest/gate.sh','--focus','main'])
assert json.loads(test_a.stdout)['passed']==1
test_b=run('dep-test-b',b,['guest/gate.sh','--focus','main'])
assert json.loads(test_b.stdout)['cached']==1 and json.loads(test_b.stdout)['executed']==0
(b/'guest/dependency.my').write_text(original.replace('return 3','return 4'))
changed=run('dep-build-edited-b',b,['guest/build-app.sh']).stdout.strip();assert changed!=first
assert run('dep-run-edited-b',b,[changed]).stdout.strip()=='4'
failed=run('dep-test-edited-b',b,['guest/gate.sh','--focus','main'],status=1)
report=json.loads(Path(json.loads(failed.stdout)['report']).read_text())
assert report['failed']==1 and report['executed']==1,report
assert run('dep-run-unmodified-a',a,[first]).stdout.strip()=='3'
unmodified=run('dep-test-unmodified-a',a,['guest/gate.sh','--focus','main'])
assert json.loads(unmodified.stdout)['cached']==1
(b/'guest/dependency.my').write_text(original)
reverted=run('dep-build-reverted-b',b,['guest/build-app.sh']);assert reverted.stdout.strip()==first
restored=run('dep-test-reverted-b',b,['guest/gate.sh','--focus','main'])
assert json.loads(restored.stdout)['cached']==1 and json.loads(restored.stdout)['executed']==0
print('real dependency invalidation and reversion: PASS',flush=True)
