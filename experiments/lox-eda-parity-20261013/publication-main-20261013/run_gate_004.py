import hashlib,json,os,subprocess,time
from pathlib import Path
root=Path.cwd(); out=root/'.tmp/parity-publication/gate-004'; out.mkdir(exist_ok=False)
prior=root/'experiments/lox-eda-parity-20261013/coordinator/common-004/inputs.json'
route=json.loads(prior.read_text())['qualified_component_inputs']
for item in route:
 p=Path(item['path']); h=hashlib.sha256()
 with p.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''): h.update(block)
 assert h.hexdigest()==item['sha256'],str(p)
pin=next(x['path'] for x in route if x['path'].endswith('.json'))
archive=next(x['path'] for x in route if x['path'].endswith('.tar'))
git=lambda *args:subprocess.check_output(['git',*args],text=True).strip()
assert not git('status','--porcelain'), 'publication checkout must be clean'
command=['python3','-B','scripts/verify_cache.py','--zig',os.environ['ZIG'],'--integration','--','-j'+os.environ['MYLANG_DEV_JOBS'],'--maxrss',os.environ['MYLANG_DEV_MAXRSS'],'-Dcomponent-owned-compiler-pin='+pin,'-Dcomponent-seed-source='+archive]
record={'source_commit':git('rev-parse','HEAD'),'source_tree':git('rev-parse','HEAD^{tree}'),'parents':git('show','-s','--format=%P','HEAD').split(),'command':command,'component_inputs':route,'started_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
(out/'command.json').write_text(json.dumps(record,indent=2)+'\n')
started=time.monotonic()
with (out/'gate.log').open('x') as log: result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
record.update(returncode=result.returncode,elapsed_seconds_including_admission=time.monotonic()-started,finished_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),status_after=git('status','--porcelain'))
(out/'status.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
raise SystemExit(result.returncode)
