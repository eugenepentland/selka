#!/usr/bin/env python3
"""Build exact frozen numeric source RC/GC guests; selected compiler, no timing."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,subprocess
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-vm-numeric-20261003';source=work/'numeric-qualified'
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();files=lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
assert files(source)==json.loads((work/'source-final.json').read_text())['candidate']
r={'source':str(source),'source37':files(source),'compiler':str(compiler),'compiler_sha256':sha(compiler),'qbe_sha256':sha(compiler.with_name('qbe')),'runs':[],'verified_after':False};assert len(r['source37'])==37
assert r['compiler_sha256']=='d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040';assert r['qbe_sha256']=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
env=dict(os.environ,TMPDIR=str(work/'tmp'));dest=work/'builds.json';assert not dest.exists()
for runtime in ['rc','gc']:
 for backend in ['qbe','llvm']:
  key='numeric-'+runtime+'-'+backend;binary=work/key;cache=work/('cache-'+key)
  argv=[str(lane/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source/'main.my'),'--project','--backend',backend]
  if backend=='llvm':argv+=['--llvm-opt','3','--lto']
  argv+=['--rc-runtime'] if runtime=='rc' else ['--gc-runtime'];argv+=['--keep-symbols','--cache-dir',str(cache),'-o',str(binary)]
  out=work/(key+'.stdout');err=work/(key+'.stderr');row={'argv':argv,'cwd':str(lane),'environment':{'TMPDIR':env['TMPDIR']},'runtime':runtime,'backend':backend,'cache':str(cache),'started':datetime.now(timezone.utc).isoformat()};print('Building',key,flush=True)
  with out.open('xb') as stdout,err.open('xb') as stderr:run=subprocess.run(argv,cwd=lane,env=env,stdout=stdout,stderr=stderr,timeout=900)
  row.update(status=run.returncode,stdout=str(out),stdout_sha256=sha(out),stderr=str(err),stderr_sha256=sha(err),finished=datetime.now(timezone.utc).isoformat())
  if run.returncode==0:
   manifest=Path(str(binary)+'.qbe-manifest.json');receipt=Path(str(binary)+'.qbe-receipt');m=json.loads(manifest.read_text());runtime_obj=Path(m['runtime_object'])
   row.update(binary=str(binary),binary_sha256=sha(binary),manifest=str(manifest),manifest_sha256=sha(manifest),receipt=str(receipt),receipt_sha256=sha(receipt),codegen={k:m[k] for k in ['abi','backend','optimization','lto','thin_lto']},runtime_object=str(runtime_obj),runtime_object_sha256=sha(runtime_obj))
  r['runs'].append(row);dest.write_text(json.dumps(r,indent=2)+'\n');assert run.returncode==0,err.read_text()
assert files(source)==r['source37'] and sha(compiler)==r['compiler_sha256'] and sha(compiler.with_name('qbe'))==r['qbe_sha256']
r['verified_after']=True;dest.write_text(json.dumps(r,indent=2)+'\n');print('4 exact RC/GC builds verified',flush=True)
