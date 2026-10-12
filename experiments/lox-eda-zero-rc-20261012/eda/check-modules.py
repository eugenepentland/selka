#!/usr/bin/env python3
"""Collect ownership diagnostics across the full module closure in one admitted lease."""
import concurrent.futures,json,pathlib,subprocess,sys
compiler=sys.argv[1];root=pathlib.Path(__file__).resolve().parent
modules=sorted((root/'source/src').glob('*.my'))
def one(module):
 result=subprocess.run([compiler,'check',str(module),'--experimental-zero-rc'],capture_output=True,text=True,timeout=120)
 return {'module':module.name,'status':result.returncode,'stdout':result.stdout,'stderr':result.stderr}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 results=list(pool.map(one,modules))
out=root/'evidence';out.mkdir(exist_ok=True)
(out/'module-checks.json').write_text(json.dumps({'compiler':compiler,'modules':results},indent=2)+'\n')
print(sum(r['status']==0 for r in results),'of',len(results),'modules pass checked ownership')
for row in results:
 if row['status']:
  print(row['module'],row['stderr'].splitlines()[0])
