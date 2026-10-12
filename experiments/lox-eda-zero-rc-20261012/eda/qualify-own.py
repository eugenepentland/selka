#!/usr/bin/env python3
"""Run currently checked EDA test modules outside delegated groups in one lease."""
import concurrent.futures,json,os,pathlib,subprocess,sys
compiler=sys.argv[1];root=pathlib.Path(__file__).resolve().parent;workspace=root.parents[2];work=workspace/'.tmp/lox-eda-20261012/eda';work.mkdir(parents=True,exist_ok=True)
checks=json.loads((root/'evidence/module-checks.json').read_text())['modules']
reserved=('board_layers','diagram_membership','design_model','eval_','flat_netlist','placement_','export_kicad','kicad_','render_')
modules=[r['module'] for r in checks if r['status']==0 and r['module'].endswith('_test.my') and not r['module'].startswith(reserved)]
env=dict(os.environ,MYL_CORE_LEAKCHECK='1',TMPDIR=str(work))
def one(name):
 cmd=[compiler,'test',str(root/'source/src'/name),'--experimental-zero-rc','--release','--verify-facts','--jobs','1','--max-steps','1000000000','--max-frames','40000','--max-memory','2G','--timeout-ms','120000','--cache-dir',str(work/'test-zero-own'/name),'--json']
 result=subprocess.run(cmd,capture_output=True,text=True,env=env,timeout=240)
 try:data=json.loads(result.stdout)
 except ValueError:data=None
 (root/'evidence'/('own-'+name+'.stdout')).write_text(result.stdout)
 (root/'evidence'/('own-'+name+'.stderr')).write_text(result.stderr)
 return {'module':name,'status':result.returncode,'passed':data.get('passed') if data else None,'failed':data.get('failed') if data else None,'stderr':result.stderr}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 rows=list(pool.map(one,modules))
(root/'evidence/test-zero-own-summary.json').write_text(json.dumps(rows,indent=2)+'\n')
for r in rows:print(r['module'],r['status'],r['passed'],r['failed'],r['stderr'][:200])
