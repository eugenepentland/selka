from pathlib import Path
import os,json,hashlib,subprocess,gzip
r=Path.cwd();w=r/'.tmp-mut-argument/caller-field-read';original=w/'controls';out=w/'controls-proof';out.mkdir(exist_ok=True)
c=w/'install-proof-final/bin/mylang';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(r.parent/'.d9-rc-mut-argument-tmp'),MYLANG_MEMORY_LIMIT='8G')
d={'compiler':str(c),'compiler_sha256':sha(c),'builds':[],'runs':[],'emissions':[]}
def save():(w/'proof-controls.json').write_text(json.dumps(d,indent=2)+'\n')
g=json.loads((original/'guests.json').read_text());e=json.loads((original/'embedding.json').read_text())
for kind,rows in (('guest',g['rows']),('embedding',e['builds'])):
 for old in rows:
  if old['side']!='after':continue
  binary=out/Path(old['binary']).name
  cmd=[str(c) if x.endswith('/install-prototype/bin/mylang') else str(binary) if x==old['binary'] else x for x in old['command']]
  p=subprocess.run(cmd,env=env,capture_output=True,text=True);row={'kind':kind,'backend':old['backend'],'command':cmd,'exit':p.returncode,'stderr':p.stderr,'binary':str(binary),'original':old['binary'],'original_sha256':old['sha256']};d['builds'].append(row);save();assert not p.returncode,row
  row.update(sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));save();assert row['sha256']==row['original_sha256'],row
  if kind=='guest':
   runenv=env.copy()
   if old['mode']=='gc':runenv['MYLANG_GC_STRESS']='1'
   q=subprocess.run([str(binary)],env=runenv,capture_output=True,text=True);record={'kind':kind,'mode':old['mode'],'backend':old['backend'],'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr};d['runs'].append(record);save();assert q.returncode==0 and q.stdout==old['run']['stdout'] and q.stderr==old['run']['stderr'],record
  else:
   for oldrun in e['runs']:
    if oldrun['side']!='after' or oldrun['backend']!=old['backend']:continue
    cmd=[str(binary) if x==old['binary'] else x for x in oldrun['command']]
    q=subprocess.run(cmd,env=env,capture_output=True,text=True);record={'kind':kind,'mode':oldrun['mode'],'backend':old['backend'],'command':cmd,'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr};d['runs'].append(record);save();assert q.returncode==0 and q.stdout==oldrun['stdout'] and q.stderr==oldrun['stderr'],record
  print(kind,old['backend'],'byte-identical and executed',flush=True)
for mode in ('plain','accounted'):
 cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'emit-qbe',str(r/'tests/lang/rc_caller_field_reads.my'),'--rc-runtime']
 if mode=='plain':cmd+=['--drop-step-checks','--drop-frame-checks']
 p=subprocess.run(cmd,env=env,capture_output=True);assert not p.returncode,p.stderr
 old=gzip.decompress((original/('after-'+mode+'.json.gz')).read_bytes());assert p.stdout==old
 d['emissions'].append({'mode':mode,'command':cmd,'exit':p.returncode,'sha256':hashlib.sha256(p.stdout).hexdigest()});save()
print('six byte-identical controls,36 exact executed runs,two exact full emissions',flush=True)
