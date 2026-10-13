#!/usr/bin/env python3
import hashlib,json,re,subprocess,sys
from pathlib import Path
binary=Path(sys.argv[1]).resolve();work=Path(sys.argv[2]);work.mkdir(parents=True,exist_ok=True)
valid={'byte-valid':'18/1\n','byte-negative':'52/0\n','constant-valid':'42/1\n','short-valid':'4660/2\n'}
cases=list(valid)+['byte-bounds','byte-max-ip','constant-code-bounds','constant-pool-bounds','constant-max-ip','string-kind','short-low-bounds','short-multiply-first','short-max-ip']
receipt={'binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'timings':'not measured','cases':[]}
for case in cases:
 arms={}
 for arm in ['legacy','scalar']:
  p=subprocess.run([str(binary),arm,case],capture_output=True,timeout=15);raw=work/f'{case}-{arm}.stderr.txt';raw.write_bytes(p.stderr);m=re.search(rb'error\[(R_[A-Z_]+)\]: ([^\n]*)',p.stderr)
  arms[arm]={'status':p.returncode,'stdout':p.stdout.decode(),'category':m.group(1).decode() if m else None,'detail':m.group(2).decode() if m else None,'stderr_sha256':hashlib.sha256(p.stderr).hexdigest(),'stderr_file':str(raw.resolve())}
 a,b=arms.values();assert (a['status'],a['stdout'],a['category'],a['detail'])==(b['status'],b['stdout'],b['category'],b['detail']),(case,arms)
 if case in valid:assert a['status']==0 and a['stdout']==valid[case] and a['category'] is None,(case,arms)
 else:assert a['status']!=0 and a['category'] is not None,(case,arms)
 if case in ['byte-max-ip','constant-max-ip']:assert a['category']=='R_LIST_BOUNDS',(case,arms)
 if case in ['short-max-ip','short-multiply-first']:assert a['category']=='R_OVERFLOW',(case,arms)
 if case=='string-kind':assert a['category']=='R_ASSERT',(case,arms)
 receipt['cases'].append({'scenario':case,'arms':arms,'status':'passed'})
(work/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('passed',len(cases),'scalar/legacy result, IP, and fatal-order comparisons')
