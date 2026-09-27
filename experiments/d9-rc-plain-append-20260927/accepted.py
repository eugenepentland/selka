from pathlib import Path
import os,subprocess,json,gzip,hashlib,statistics,time
r=Path.cwd();w=r/'.tmp-rc/append-room';old=json.load(gzip.open(r/'experiments/d9-rc-owned-loops-composed-20260927/results.json.gz'))
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
while True:
 try:
  current=json.loads((w/'full/results.json').read_text())
  if len(current['runs'])==64 and 'counts' in current['runs'][-1]:break
 except (FileNotFoundError,json.JSONDecodeError):pass
 time.sleep(5)
d={'accepted_compilers':old['compilers'] if 'compilers' in old else None,'runs':[],'ratios':{}}
for row in old['runs']:
 if row['side']!='gc' or row['repeat']!=0:continue
 key=row['key'];cmd=list(row['command']);binary=Path(cmd[-1]);digest=hashlib.sha256(binary.read_bytes()).hexdigest();assert digest==row['binary_sha256']
 counts=[]
 for repeat in range(3):
  stat=w/f'accepted-{key}-{repeat}.stat';cmd[cmd.index('-o')+1]=str(stat)
  p=subprocess.run(cmd,env=env,text=True,capture_output=True,timeout=600);raw=stat.read_text();count=next(int(s.split(',')[0]) for s in raw.splitlines() if 'instructions' in s and s.split(',')[0].isdigit())
  result=dict(key=key,repeat=repeat,command=cmd.copy(),status=p.returncode,stdout=p.stdout,stderr=p.stderr,perf=raw,instructions=count,binary_sha256=digest);d['runs'].append(result)
  assert p.returncode==0 and p.stdout==row['stdout'],result
  counts.append(count)
  (w/'accepted.json').write_text(json.dumps(d,indent=2)+'\n')
 name=next(n for n in ['alloc','fannkuch','sieve','append'] if {'alloc':'alloc_churn','fannkuch':'fannkuch_redux','sieve':'sieve','append':'list_append_sum'}[n] in key)
 backend=key.rsplit('.',1)[1];rc=current['medians'][name+'-after-'+backend];gc=statistics.median(counts)
 d['ratios'][key]={'gc':gc,'rc':rc,'rc_gc':rc/gc};(w/'accepted.json').write_text(json.dumps(d,indent=2)+'\n');print(key,rc/gc,flush=True)
