"""Unscored full-contract resource reproducers; prints status without hiding failures."""
import json
import subprocess
import time
from test_cli import HOST, ROOT, job, manifest
names=['j'+str(i).zfill(3) for i in range(128)]
for name,jobs in [('dense-cycle',[job(n,1,names) for n in names]),('maximum-distinct-unknown',[job(n,1,['x'+str(i*128+j).zfill(5) for j in range(128)]) for i,n in enumerate(names)])]:
    start=time.monotonic()
    try:
        result=subprocess.run([str(HOST),'--project',str(ROOT)], input=json.dumps(dict(cases=[manifest(jobs)])).encode(),capture_output=True,timeout=180)
        print(name, 'exit',result.returncode,'seconds',round(time.monotonic()-start,3),'output bytes',len(result.stdout),'stderr',result.stderr.decode(),flush=True)
        if result.returncode==0:
            data=json.loads(result.stdout)['results'][0]
            assert data['error']==('cycle' if name=='dense-cycle' else 'unknown-dependency')
            assert len(data['blocked' if name=='dense-cycle' else 'ids'])==(128 if name=='dense-cycle' else 16384)
    except subprocess.TimeoutExpired:
        print(name,'timeout after 180 seconds',flush=True)
