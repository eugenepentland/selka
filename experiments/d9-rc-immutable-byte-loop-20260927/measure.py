from pathlib import Path
import os,json,subprocess,hashlib,time,statistics
r=Path.cwd();w=r/'.tmp-bytes';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();build=json.loads((w/'benchmark-builds.json').read_text());expected=(r/'bench/parity/micro/bytes_scan.expected').read_text();e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e.update(TMPDIR=str(w/'tmp'),MYLANG_MEMORY_LIMIT='8G')
for c in build['compilers'].values():assert sha(Path(c['path']))==c['sha256']
assert len(build['rows'])==8
result={'cpu':10,'source_sha256':build['source_sha256'],'expected_sha256':hashlib.sha256(expected.encode()).hexdigest(),'runs':[]}
def save():(w/'measurements.json').write_text(json.dumps(result,indent=2)+'\n')
for backend in ['qbe','llvm']:
 for phase,reps in [('counts',1),('instructions',3),('rss',3)]:
  for repeat in range(reps):
   for arm in (['before','after'] if repeat%2==0 else ['after','before']):
    b=next(x for x in build['rows'] if x['arm']==arm and x['backend']==backend and x['counted']==(phase=='counts'));p=Path(b['binary']);assert sha(p)==b['binary_sha256']
    extra=['perf','stat','-x,','-e','cpu_core/instructions/u','--'] if phase=='instructions' else ['/usr/bin/time','-f','GUEST_RSS_KIB=%M'] if phase=='rss' else []
    cmd=['taskset','-c','10',*extra,str(p)];start=time.monotonic();out=subprocess.run(cmd,env=e,capture_output=True,text=True,timeout=90);row=dict(arm=arm,backend=backend,phase=phase,repeat=repeat,command=cmd,exit=out.returncode,stdout=out.stdout,stderr=out.stderr,wall_seconds=time.monotonic()-start,binary_sha256=sha(p));result['runs'].append(row);save();assert out.returncode==0 and out.stdout==expected,row
    if phase=='counts':
     cts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in out.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=cts;assert not cts['saturated'] and cts['heap_allocate']==cts['retire'] and cts['owner_acquire']+cts['heap_allocate']==cts['owner_release'] and cts['hold_acquire']==cts['hold_release'],row
    elif phase=='instructions':
     f=next(x.split(',') for x in out.stderr.splitlines() if ',cpu_core/instructions/u,' in x);row.update(instructions=int(f[0]),event_runtime_ns=int(f[3]),event_running_percent=float(f[4]));assert row['event_running_percent']==100.0,row
    else:row['guest_max_rss_kib']=int(next(x.removeprefix('GUEST_RSS_KIB=') for x in out.stderr.splitlines() if x.startswith('GUEST_RSS_KIB=')))
    save();print('DONE',backend,phase,repeat,arm,round(row['wall_seconds'],3),row.get('instructions',row.get('guest_max_rss_kib',row.get('counts'))),flush=True)
for backend in ['qbe','llvm']:
 a,b=[x for x in result['runs'] if x['backend']==backend and x['phase']=='counts'];assert a['counts']==b['counts']
print('COMPLETE',flush=True)
