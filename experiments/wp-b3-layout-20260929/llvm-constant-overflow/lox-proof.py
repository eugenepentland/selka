import hashlib,json,os,subprocess
from pathlib import Path
w=Path(__file__).resolve().parent.parent;r=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-next-closeout-20260929');p=r/'.tmp-rc-quick/lox/benchmarks/lox/ports/mylang';d=w/'.tmp/lox-final-proof';d.mkdir(exist_ok=True)
hashfile=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
compiler=w/'.tmp/constant-final/bin/mylang';qbe=w/'.tmp/constant-final/bin/qbe';sources={str(x.relative_to(p)):hashfile(x) for x in p.rglob('*.my')}
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_')};e.update(TMPDIR=str(w/'.tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'.zig-local-cache'),ZIG_GLOBAL_CACHE_DIR=str(w/'.zig-global-cache'),MYLANG_LLVM_DUMP=str(d/'dump'))
cmd=[str(w/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(d/'lox.llvm'),'--backend','llvm','--llvm-opt','3','--lto','--rc-runtime','--keep-symbols','--cache-dir',str(d/'cache')]
with (d/'build.out').open('wb') as out,(d/'build.err').open('wb') as err:done=subprocess.run(cmd,cwd=p,env=e,stdout=out,stderr=err)
receipt={'compiler_sha256':hashfile(compiler),'qbe_sha256':hashfile(qbe),'command':cmd,'status':done.returncode,'project_sources':sources}
(d/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print('build',done.returncode,flush=True);assert done.returncode==0
receipt['binary_sha256']=hashfile(d/'lox.llvm')
for name,tool in [('assembly',['objdump','-d','--no-show-raw-insn']),('symbols',['nm','-n','-S'])]:(d/name).write_bytes(subprocess.check_output(tool+[str(d/'lox.llvm')]))
input=r/'.tmp-rc-quick/lox-scripts/invocation.n30000.lox';cmd=[str(w/'scripts/build-slot.sh'),'build',str(d/'lox.llvm'),'--engine=vm',str(input)];run=subprocess.run(cmd,capture_output=True,env=e);(d/'stdout').write_bytes(run.stdout);(d/'stderr').write_bytes(run.stderr);receipt['run']={'command':cmd,'status':run.returncode,'stdout':run.stdout.decode(),'stderr':run.stderr.decode(),'input_sha256':hashfile(input)}
assert run.returncode==0 and run.stdout==b'30000\n' and not run.stderr
assert sources=={str(x.relative_to(p)):hashfile(x) for x in p.rglob('*.my')}
vm='myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29';ir=(d/'dump'/f'{vm}.ll').read_text();receipt['vm_ssub_calls']=ir.count('call { i64, i1 } @llvm.ssub.with.overflow.i64');receipt['vm_sadd_calls']=ir.count('call { i64, i1 } @llvm.sadd.with.overflow.i64');receipt['vm_bound_icmp']=ir.count('9223372036854775807')+ir.count('9223372036854775806');(d/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print('run',run.returncode,run.stdout.decode().strip(),'vm_ssub',receipt['vm_ssub_calls'],flush=True)
