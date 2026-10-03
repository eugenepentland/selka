#!/usr/bin/env python3
"""Explicit provider-backed execution of the added constant operand regression."""
from pathlib import Path
import hashlib,json,os,subprocess
lane=Path(__file__).resolve().parents[2]
work=lane/'.tmp-lox-composed-20261003'
source=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-round3/combined')
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
files=lambda d:{str(p.relative_to(d)):sha(p) for p in sorted(d.rglob('*')) if p.is_file()}
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env['TMPDIR']=str(work/'tmp')
receipt={'source37':files(source),'compiler_sha256':sha(compiler),'qbe_sha256':sha(compiler.with_name('qbe')),'runs':[],'verified_after':False}
output=work/'provider-qualification.json';assert not output.exists()
for backend in ['llvm','qbe']:
 for runtime in ['rc','gc-stress']:
  key='provider-'+backend+'-'+runtime
  argv=[str(lane/'scripts/build-slot.sh'),'build',str(compiler),'test',str(source/'driver_tests.my'),
        '--cases',str(source/'driver_cases.json'),'--filter','test_run_constant_operand_last_byte',
        '--json','--jobs','2','--max-steps','1000000000','--timeout-ms','120000',
        '--cache-dir',str(work/('cache-'+key))]
  argv+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
  argv+=['--rc-runtime'] if runtime=='rc' else ['--gc-stress']
  out=work/(key+'.json');err=work/(key+'.stderr');print('Explicit provider',key,flush=True)
  with out.open('wb') as stdout,err.open('wb') as stderr:run=subprocess.run(argv,cwd=lane,env=env,stdout=stdout,stderr=stderr,timeout=900)
  receipt['runs'].append({'argv':argv,'cwd':str(lane),'TMPDIR':env['TMPDIR'],'status':run.returncode,
                         'stdout':str(out),'stdout_sha256':sha(out),'stderr':str(err),'stderr_sha256':sha(err)})
  output.write_text(json.dumps(receipt,indent=2)+'\n');assert run.returncode==0,(out,err)
  data=json.loads(out.read_text());print('Provider report keys',list(data),flush=True)
assert files(source)==receipt['source37'] and sha(compiler)==receipt['compiler_sha256'] and sha(compiler.with_name('qbe'))==receipt['qbe_sha256']
receipt['verified_after']=True;output.write_text(json.dumps(receipt,indent=2)+'\n')
print('Four explicit provider-backed executions complete',flush=True)
