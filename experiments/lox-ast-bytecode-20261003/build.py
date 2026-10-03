#!/usr/bin/env python3
"""Build four checked combined guests on frozen d14/99ad; no measurements."""
from datetime import datetime,timezone
import hashlib,json,os,subprocess
from pathlib import Path
OWN = Path(__file__).resolve().parents[2]
WORK = OWN/'.tmp-lox-ast-bytecode-20261003'
SOURCE = WORK/'candidate'
COMPILER = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda p:{str(x.relative_to(p)):sha(x) for x in sorted(p.rglob('*')) if x.is_file()}
manifest = json.loads((OWN/'experiments/lox-ast-bytecode-20261003/source.json').read_text())
assert files(SOURCE) == manifest['candidate37']
receipt = {'source':str(SOURCE),'source37':files(SOURCE),'compiler':str(COMPILER),'compiler_sha256':sha(COMPILER),'qbe_sha256':sha(COMPILER.with_name('qbe')),'runs':[],'verified_after':False}
assert receipt['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert receipt['qbe_sha256'] == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
assert not (WORK/'builds.json').exists()
assert not set(os.sched_getaffinity(0)) & {2,3,10,11}
env = {k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env['TMPDIR'] = str(WORK/'tmp')
for runtime in ['rc','gc']:
    for backend in ['llvm','qbe']:
        key = runtime+'-'+backend
        binary = WORK/('combined-'+key)
        argv = [str(OWN/'scripts/build-slot.sh'),'build',str(COMPILER),'build',str(SOURCE/'main.my'),'--project','--backend',backend]
        if backend == 'llvm':argv += ['--llvm-opt','3','--lto']
        argv += ['--'+runtime+'-runtime','--keep-symbols','--cache-dir',str(WORK/('cache-build-'+key)),'-o',str(binary)]
        log = WORK/('build-'+key+'.log')
        print('Building checked combined guest',key,flush=True)
        start = datetime.now(timezone.utc).isoformat()
        with log.open('wb') as out:run = subprocess.run(argv,cwd=OWN,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=900)
        row = {'key':key,'argv':argv,'cwd':str(OWN),'TMPDIR':env['TMPDIR'],'started_utc':start,'finished_utc':datetime.now(timezone.utc).isoformat(),'status':run.returncode,'log':str(log),'log_sha256':sha(log)}
        receipt['runs'].append(row)
        (WORK/'builds.json').write_text(json.dumps(receipt,indent=2)+'\n')
        assert run.returncode == 0,(key,log)
        metadata = Path(str(binary)+'.qbe-manifest.json')
        runtime_object = Path(json.loads(metadata.read_text())['runtime_object'])
        row.update(binary=str(binary),binary_sha256=sha(binary),manifest=str(metadata),manifest_sha256=sha(metadata),receipt_sha256=sha(str(binary)+'.qbe-receipt'),runtime_object=str(runtime_object),runtime_object_sha256=sha(runtime_object))
        (WORK/'builds.json').write_text(json.dumps(receipt,indent=2)+'\n')
assert files(SOURCE) == receipt['source37']
assert sha(COMPILER) == receipt['compiler_sha256'] and sha(COMPILER.with_name('qbe')) == receipt['qbe_sha256']
for row in receipt['runs']:
    assert sha(row['binary']) == row['binary_sha256'] and sha(row['runtime_object']) == row['runtime_object_sha256']
receipt['verified_after'] = True
(WORK/'builds.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('Four checked combined ELFs frozen; source37/compiler/QBE identities unchanged.',flush=True)
