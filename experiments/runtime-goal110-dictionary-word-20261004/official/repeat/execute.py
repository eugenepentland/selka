from pathlib import Path
import json,hashlib,subprocess,uuid,datetime
p=Path(__file__).with_name('commands.json');d=json.loads(p.read_text());h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for path,expected in d['helper_sha256'].items():assert h(path)==expected
for binding in [*d['manifests'].values(),d['readiness'],d['plans']]:assert h(binding['path'])==binding['sha256']
r={'schema':'mylang-dictionary-word-repeat-driver-v1','driver_session_id':str(uuid.uuid4()),'commands_sha256':h(p),'driver_sha256':h(__file__),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':d['command']}
with p.with_name('repeat.log').open('x') as out:
 proc=subprocess.Popen(d['command'],cwd=d['cwd'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 for line in proc.stdout:out.write(line);out.flush();print(line,end='',flush=True)
 r['status']=proc.wait()
r.update(finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),log_sha256=h(p.with_name('repeat.log')));p.with_name('driver-receipt.json').write_text(json.dumps(r,indent=2)+'\n');raise SystemExit(r['status'])
