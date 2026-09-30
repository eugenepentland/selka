import hashlib,json,re,subprocess
from pathlib import Path
root=Path.cwd();folder=root/'.tmp/plain-query/guest-final';folder.mkdir(exist_ok=True);compiler=root/'.tmp/plain-query/compiler/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rows=[]
for program,path,modes in [('fannkuch','bench/parity/suite/fannkuch_redux',['qbe','llvm-full']),('alloc','bench/parity/micro/alloc_churn',['qbe','llvm-none','llvm-full','llvm-thin'])]:
 source=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-next-closeout-20260929')/(path+'.my');expected=(root/(path+'.expected')).read_text()
 emit=subprocess.run([str(compiler),'emit-qbe',str(source)],capture_output=True,text=True);assert emit.returncode==0; (folder/(program+'-emitted.json')).write_text(emit.stdout);manifest=json.loads(emit.stdout)
 il='\n'.join(f['il'] for f in manifest['functions']);(folder/(program+'-emitted.ssa')).write_text(il)
 ordinary=il.count('call $myl_rc_list_plain_ready(');hot=il.count('call $myl_rc_list_plain_ready_hot(')
 assert (ordinary,hot)==((3,0) if program=='fannkuch' else (0,1)),(program,ordinary,hot)
 for mode in modes:
  dest=folder/(program+'-'+mode);dest.mkdir(exist_ok=True);binary=dest/program
  flags=['--backend','qbe'] if mode=='qbe' else ['--backend','llvm','--llvm-opt','3']
  if mode=='llvm-full':flags+=['--lto=full']
  if mode=='llvm-thin':flags+=['--lto=thin']
  cmd=[str(compiler),'build',str(source),'-o',str(binary),'--rc-runtime','--keep-symbols','--cache-dir',str(folder/'cache')]+flags
  print('build',program,mode,flush=True);r=subprocess.run(cmd,capture_output=True,text=True);(dest/'build.stdout').write_text(r.stdout);(dest/'build.stderr').write_text(r.stderr);assert r.returncode==0,r.stderr
  run=subprocess.run(['taskset','-c','4',str(binary)],capture_output=True,text=True);(dest/'run.stdout').write_text(run.stdout);(dest/'run.stderr').write_text(run.stderr);assert run.returncode==0 and run.stdout==expected,(program,mode,run.stdout,run.stderr)
  asm=subprocess.check_output(['objdump','-d',str(binary)],text=True);(dest/'assembly.txt').write_text(asm)
  calls=[l for l in asm.splitlines() if re.search(r'\bcall\w*\s.*<myl_rc_list_plain_ready(?:_hot)?(?:[+>])',l)]
  hot_calls=[l for l in calls if '_hot' in l]
  if program=='alloc':assert (len(hot_calls)==0)==(mode in ['llvm-full','llvm-thin']),(program,mode,calls)
  else:assert not hot_calls and len(calls)==(6 if mode=='qbe' else 3),(program,mode,calls)
  rows.append(dict(program=program,mode=mode,command=cmd,status=0,stdout=run.stdout,emitted_ordinary_calls=ordinary,emitted_hot_calls=hot,machine_calls=calls,binary_sha256=sha(binary),source_sha256=sha(source),assembly_sha256=sha(dest/'assembly.txt')))
  print('pass',program,mode,'query calls',len(calls),flush=True)
(folder/'receipt.json').write_text(json.dumps(rows,indent=2)+'\n')
