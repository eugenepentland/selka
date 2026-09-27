from pathlib import Path
import os,json,subprocess
r=Path.cwd();w=r/'.tmp-bytes';e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};rows=[]
for backend in ['qbe','llvm']:
 for budget in [175,190]:
  for arm in ['before','after']:
   command=[str(w/f'trap-{arm}-{backend}-steps'),'ok'];p=subprocess.run(command,env=e|{'MYLANG_OPTIONS':f'--max-steps={budget}'},capture_output=True,text=True,timeout=10);row=dict(backend=backend,budget=budget,arm=arm,command=command,exit=p.returncode,stdout=p.stdout,stderr=p.stderr);rows.append(row);assert p.returncode==1 and 'R_STEP_LIMIT' in p.stderr and p.stdout=='before\n',row
   c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'] and not c['saturated']
  assert rows[-2]['counts']==rows[-1]['counts']
(w/'step-boundaries.json').write_text(json.dumps(rows,indent=2)+'\n');print('8 MATCHED LOOP STEP TRAPS')
