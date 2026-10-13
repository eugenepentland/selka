#!/usr/bin/env python3
"""Compare fatal diagnostic category/details of legacy and fused short readers."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
binary=Path(sys.argv[1]).resolve(); work=Path(sys.argv[2]);work.mkdir(parents=True,exist_ok=True)
scenarios=['valid','ip-overflow','high-bounds','low-bounds','multiply-before-low-bounds','multiply-negative-overflow','add-overflow','handle-bounds','kind-failure']
receipt={'binary':str(binary),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'timings':'not measured','cases':[]}
for case in scenarios:
 results={}
 for arm in ['legacy','fused']:
  p=subprocess.run([str(binary),arm,case],capture_output=True,timeout=15)
  raw=work/f'{case}-{arm}.stderr.txt';raw.write_bytes(p.stderr)
  category=re.search(rb'error\[(R_[A-Z_]+)\]: ([^\n]*)',p.stderr)
  results[arm]={'status':p.returncode,'stdout':p.stdout.decode(),'diagnostic_category':category.group(1).decode() if category else None,'diagnostic_detail':category.group(2).decode() if category else None,'stderr_file':str(raw.resolve()),'stderr_sha256':hashlib.sha256(p.stderr).hexdigest()}
 a,b=results['legacy'],results['fused']
 assert a['status']==b['status'] and a['stdout']==b['stdout'],(case,results)
 if case=='valid': assert a['status']==0 and a['stdout']=='4660\n' and a['diagnostic_category'] is None,(case,results)
 else:
  assert a['status']!=0 and a['diagnostic_category'] is not None,(case,results)
  assert a['diagnostic_category']==b['diagnostic_category'] and a['diagnostic_detail']==b['diagnostic_detail'],(case,results)
  if case in ['ip-overflow','multiply-before-low-bounds','multiply-negative-overflow','add-overflow']:
   assert a['diagnostic_category']=='R_OVERFLOW',(case,results)
   op='mul' if case.startswith('multiply') else 'add'
   assert '('+op+':' in a['diagnostic_detail'],(case,results)
 receipt['cases'].append({'scenario':case,'arms':results,'status':'passed'})
(work/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('passed',len(scenarios),'legacy/fused fatal-category and detail comparisons')
