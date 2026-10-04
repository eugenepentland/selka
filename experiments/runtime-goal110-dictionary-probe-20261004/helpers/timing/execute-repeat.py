from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,subprocess,uuid
p=argparse.ArgumentParser();p.add_argument('--commands',type=Path,required=True);p.add_argument('--expected-sha256',required=True);p.add_argument('--phase',choices=['measurements'],required=True);a=p.parse_args()
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();assert h(a.commands)==a.expected_sha256
d=json.loads(a.commands.read_text());work=a.commands.parent
for path,expected in d['helper_sha256'].items():assert h(path)==expected
for binding in [*d['manifests'].values(),d['readiness'],d['plan_binding'],d['original_commands']]:assert h(binding['path'])==binding['sha256']
receipt={'schema':'mylang-dictionary-probe-timing-driver-v1','driver_session_id':str(uuid.uuid4()),'phase':a.phase,'started_utc':datetime.now(timezone.utc).isoformat(),'commands':{'path':str(a.commands.resolve()),'sha256':h(a.commands)},'script':{'path':str(Path(__file__).resolve()),'sha256':h(__file__)},'runs':[]}
indices=[0]
for i in indices:
 command=d['commands'][i];log=work/('repeat-command-'+str(i)+'.log');row={'command':command,'started_utc':datetime.now(timezone.utc).isoformat(),'log':str(log)}
 with log.open('x') as out:
  proc=subprocess.Popen(command,cwd=d['cwd'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
  for line in proc.stdout:out.write(line);out.flush();print(line,end='',flush=True)
  row['status']=proc.wait()
 row.update(finished_utc=datetime.now(timezone.utc).isoformat(),log_sha256=h(log));receipt['runs'].append(row)
 receipt['finished_utc']=datetime.now(timezone.utc).isoformat();(work/('repeat-driver-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
 if row['status']!=0:raise SystemExit(row['status'])
print('PASS '+a.phase+' driver; all commands exit0',flush=True)
