"""Observe actual pinned QBE pass dumps; no compiler/guest changes or execution."""
from pathlib import Path
import hashlib,json,os,subprocess,time
OWN=Path(__file__).resolve().parents[2]
WORK=OWN/'.tmp-lox-private-alias-ablation-20261003'
QBE=OWN/'.tmp-lox-qbe-dispatch-20261003/compiler-v3/bin/qbe'
SOURCES=[OWN/'vendor/qbe/mem.c',OWN/'vendor/qbe/main.c']
HASH=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
TRACKED=[QBE,Path(__file__),*[WORK/(a+'.ssa') for a in ['control','s1-one']],*SOURCES]
before={str(p):HASH(p) for p in TRACKED}
assert before[str(QBE)]=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env['TMPDIR']=str(WORK/'tmp')
r={'scope':'static actual pinned QBE internal pass dumps only; repository vendor files are explanatory source, not separately proved complete executable build provenance','before':before,'commands':[],'verified_after':False}
for arm in ['control','s1-one']:
 out=WORK/(arm+'.debug.stdout');err=WORK/(arm+'.debug.stderr');assert not out.exists() and not err.exists()
 argv=[str(OWN/'scripts/build-slot.sh'),'build',str(QBE),'-d','MG',str(WORK/(arm+'.ssa'))]
 start=time.time();p=subprocess.run(argv,cwd=OWN,env=env,capture_output=True);out.write_bytes(p.stdout);err.write_bytes(p.stderr)
 r['commands'].append({'arm':arm,'argv':argv,'cwd':str(OWN),'TMPDIR':env['TMPDIR'],'started':start,'finished':time.time(),'status':p.returncode,'stdout':str(out),'stdout_sha256':HASH(out),'stderr':str(err),'stderr_sha256':HASH(err)})
 (WORK/'debug-receipt.json').write_text(json.dumps(r,indent=2)+'\n');p.check_returncode()
after={str(p):HASH(p) for p in TRACKED};assert before==after
r.update(after=after,verified_after=True);(WORK/'debug-receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'statuses':[v['status'] for v in r['commands']],'verified_after':True}))
