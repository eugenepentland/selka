import pathlib,json,subprocess,os,hashlib,shutil
from counter_policy import compare
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack';work=root/'.tmp/lox-eda-parity/P7-stack';out=base/'counter-repeats-001';out.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build';q=json.loads((base/'qualification-005/receipt.json').read_text());rows=[]
for row in q['commands']:
 if row['case']!='eda-rds3+flat' or row['arm'] not in ['installed-C2-counted','counted-control','counted-candidate']:continue
 for n in range(2):
  label=row['arm']+str(n);counter=out/(label+'.counts.json');argv=row['argv'];directory=pathlib.Path(argv[argv.index('--out-dir')+1]);shutil.rmtree(directory,ignore_errors=True);r=subprocess.run(argv,cwd=row['cwd'],env={**os.environ,'MYLANG_COUNTERS':str(counter),'MYL_CORE_LEAKCHECK':'1'},capture_output=True,timeout=120);(out/(label+'.stdout')).write_bytes(r.stdout);(out/(label+'.stderr')).write_bytes(r.stderr);assert r.returncode==0;assert hashlib.sha256(r.stdout).hexdigest()==row['stdout_sha256'];assert hashlib.sha256(r.stderr).hexdigest()==row['stderr_sha256'];v=json.loads(counter.read_text());reference=json.loads((base/'qualification-005'/(row['case']+'-'+row['arm']+'.counts.json')).read_text())
  def stable(a):
   if isinstance(a,dict):return {k:stable(v) for k,v in a.items() if k not in ['realloc_moves','realloc_moved_bytes']}
   if isinstance(a,list):return [stable(v) for v in a]
   return a
  compare(reference,v);rows.append({'arm':row['arm'],'repeat':n,'argv':argv,'returncode':r.returncode,'counter_file':str(counter),'totals':v['totals']});print(label,flush=True)
(out/'receipt.json').write_text(json.dumps({'status':'passed','counter_policy':'All fields except allocator-placement realloc_moves/realloc_moved_bytes identical; all raw fields retained','commands':rows},indent=2)+'\n')
