#!/usr/bin/env python3
"""Compare CLI/model/filesystem errors across explicit EDA executable arms."""
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parent;workspace=root.parents[1];work=workspace/'.tmp/lox-eda-improvements-20261012/eda/error-paths';work.mkdir(parents=True,exist_ok=True)
reference=pathlib.Path('/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore')
fixtures={'unterminated-form':b'(sch-model 1\n','wrong-root':b'(wrong-root 1)\n','unsupported-version':b'(sch-model 99)\n','empty-model':b''}
for name,contents in fixtures.items():(work/(name+'.sexp')).write_bytes(contents)
base=['--project-dir',str(reference/'golden/projects/designs'),'--out-dir',str(work/'out')]
cases={'no-args':([],2),'unknown-option':(['--unknown'],2),'missing-value':(['--model'],2),'missing-file':(['--model',str(work/'absent.sexp'),*base],1)}
for name in fixtures:cases[name]=(['--model',str(work/(name+'.sexp')),*base],1)
# An existing ordinary file cannot serve as the output directory.
blocked=work/'blocked-output';blocked.write_bytes(b'ordinary file\n')
cases['invalid-output-dir']=(['--model',str(reference/'golden/cases/rds3+flat/model.sexp'),'--project-dir',str(reference/'golden/projects/designs'),'--out-dir',str(blocked),'--flat'],1)
arms=[(s.split('=',1)[0],pathlib.Path(s.split('=',1)[1]).resolve()) for s in sys.argv[1:]]
if len(arms)<2:raise SystemExit('provide at least two name=/absolute/binary arms')
rows=[]
for name,(args,expected) in cases.items():
 results=[]
 for label,binary in arms:
  result=subprocess.run([str(binary),*args],capture_output=True,timeout=120)
  results.append({'arm':label,'status':result.returncode,'stdout':result.stdout.decode(errors='backslashreplace'),'stderr':result.stderr.decode(errors='backslashreplace')})
 first=results[0]
 rows.append({'case':name,'args':args,'expected_status':expected,'outputs_identical':all((r['status'],r['stdout'],r['stderr'])==(first['status'],first['stdout'],first['stderr']) for r in results),'expected_status_matches':all(r['status']==expected for r in results),'arms':results})
report={'binaries':{label:{'path':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()} for label,binary in arms},'cases':rows,'pass':all(r['outputs_identical'] and r['expected_status_matches'] for r in rows)}
(root/'error-paths.json').write_text(json.dumps(report,indent=2)+'\n')
print(len(rows),'error paths;', 'PASS' if report['pass'] else 'FAIL')
raise SystemExit(0 if report['pass'] else 1)
