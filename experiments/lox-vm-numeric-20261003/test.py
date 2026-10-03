#!/usr/bin/env python3
"""Fresh accounted suites for immutable source; no timing."""
from pathlib import Path
import hashlib,json,os,re,subprocess
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-vm-numeric-20261003';source=work/'numeric-qualified'
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();files=lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
expected={f.stem+'::'+name for f in source.glob('*.my') for name in re.findall(r'^public def (test_[A-Za-z0-9_]+)\(',f.read_text(),re.M)};assert len(expected)==87
frozen=json.loads((work/'source-final.json').read_text());assert files(source)==frozen['candidate']
env=dict(os.environ,TMPDIR=str(work/'tmp'))
r={'source':str(source),'source37':files(source),'expected_names':sorted(expected),'compiler':str(compiler),'compiler_sha256':sha(compiler),'qbe_sha256':sha(compiler.with_name('qbe')),'runs':[],'verified_after':False,'provider_scope':'directory runs omit --cases; fixture entries preserved structurally, not claimed provider-backed execution'}
assert r['compiler_sha256']=='d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040';assert r['qbe_sha256']=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
dest=work/'public.json';assert not dest.exists()
for backend in ['qbe','llvm']:
 for runtime in ['rc','gc-stress']:
  key='public-'+backend+'-'+runtime
  argv=[str(lane/'scripts/build-slot.sh'),'build',str(compiler),'test',str(source),'--json','--force','--jobs','2','--max-steps','1000000000','--timeout-ms','120000','--cache-dir',str(work/('cache-'+key))]
  argv+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast'];argv+=['--rc-runtime'] if runtime=='rc' else ['--gc-stress']
  stdout=work/(key+'.json');stderr=work/(key+'.stderr');print('Testing',key,flush=True)
  with stdout.open('xb') as out,stderr.open('xb') as err:run=subprocess.run(argv,cwd=lane,env=env,stdout=out,stderr=err,timeout=900)
  row={'argv':argv,'cwd':str(lane),'environment':{'TMPDIR':env['TMPDIR']},'status':run.returncode,'stdout':str(stdout),'stdout_sha256':sha(stdout),'stderr':str(stderr),'stderr_sha256':sha(stderr),'backend':backend,'runtime':runtime};r['runs'].append(row);dest.write_text(json.dumps(r,indent=2)+'\n')
  assert run.returncode==0,stderr.read_text()
  doc=json.loads(stdout.read_text());row['summary']={k:doc[k] for k in ['version','passed','failed','skipped','cached','executed'] if k in doc}
  def tests(node):
   if isinstance(node,dict):
    if isinstance(node.get('tests'),list):
     for item in node['tests']:
      if isinstance(item,dict) and 'name' in item and 'status' in item:yield item
    for k,v in node.items():
     if k!='tests':yield from tests(v)
   elif isinstance(node,list):
    for v in node:yield from tests(v)
  observed=list(tests(doc));row['names']=sorted(t['name'] for t in observed)
  assert len(observed)==87 and set(row['names'])==expected,(key,len(observed),set(row['names'])^expected,doc.keys())
  assert all(t['status']=='passed' for t in observed),key
  assert doc['passed']==doc['executed']==87 and doc['failed']==doc['skipped']==doc['cached']==0,key
  dest.write_text(json.dumps(r,indent=2)+'\n');print(key,'87 fresh pass',flush=True)
assert files(source)==r['source37'] and sha(compiler)==r['compiler_sha256'] and sha(compiler.with_name('qbe'))==r['qbe_sha256']
r['verified_after']=True;dest.write_text(json.dumps(r,indent=2)+'\n');print('348 fresh passes across4 configurations',flush=True)
