#!/usr/bin/env python3
"""Check complete EDA generated output sets against all34 frozen byte goldens."""
import concurrent.futures,hashlib,json,pathlib,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parent;workspace=root.parents[2];work=workspace/'.tmp/lox-eda-20261012/eda/golden-check';reference=pathlib.Path('/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore');manifest=json.loads((reference/'golden/manifest.json').read_text())
arms=[(s.split('=',1)[0],pathlib.Path(s.split('=',1)[1]).resolve()) for s in sys.argv[1:]]
if not arms:raise SystemExit('provide name=/absolute/binary arms')
def one(task):
 label,binary,case=task;dest=work/label/case['id']
 if dest.exists():shutil.rmtree(dest)
 dest.mkdir(parents=True)
 args=['--model',str(reference/'golden/cases'/case['id']/'model.sexp'),'--project-dir',str(reference/'golden/projects'/case['project']),'--out-dir',str(dest),*case['flags']]
 result=subprocess.run([str(binary),*args],capture_output=True,timeout=120)
 actual={str(p.relative_to(dest)):hashlib.sha256(p.read_bytes()).hexdigest() for p in dest.rglob('*') if p.is_file()};expected={n:m['sha256'] for n,m in case['outputs'].items()}
 row={'arm':label,'case':case['id'],'status':result.returncode,'files_match':actual==expected,'actual':actual,'stdout':result.stdout.decode(errors='backslashreplace'),'stderr':result.stderr.decode(errors='backslashreplace')}
 shutil.rmtree(dest)
 return row
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(one,[(label,binary,c) for label,binary in arms for c in manifest['cases']]))
report={'binaries':{label:{'path':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()} for label,binary in arms},'cases':rows,'pass':all(r['status']==0 and r['files_match'] for r in rows)}
(root/'evidence/goldens.json').write_text(json.dumps(report,indent=2)+'\n')
print(sum(r['status']==0 and r['files_match'] for r in rows),'/',len(rows),'arm-case output sets byte-identical')
raise SystemExit(0 if report['pass'] else 1)
