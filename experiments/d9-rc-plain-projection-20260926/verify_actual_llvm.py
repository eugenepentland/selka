import importlib.util,os,json,hashlib,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-schematic/schematic-actual-llvm';work.mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('compare',root.parent/'d9-rc-performance/experiments/d9-rc-acceptance-20260926/compare.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
pc=m.pc;pc.WORK=work
os.environ['TMPDIR']=str(root/'.tmp-schematic/tmp');os.environ['ZIG_LOCAL_CACHE_DIR']=str(root/'.zig-cache-schematic')
compiler=root/'.tmp-schematic/install-before-frame/bin/mylang'
programs=[p for p in m.programs() if p['kind']=='schematic'];assert len(programs)==3
binary=work/'schematic.llvm';command,cwd=pc.build_command(programs[0],str(compiler),'llvm',binary,work/'cache');command+=['--rc-runtime=stats'];assert not any(a.startswith('--qbe') for a in command)
result={'source_commit':'a49441c1','purpose':'actual LLVM replacement validation for earlier mislabeled plain-projection evidence','compiler_sha256':m.sha(compiler),'build':pc.do_build({'cmd':[str(root/'scripts/build-slot.sh'),'build',*command],'cwd':cwd,'bin':binary}),'checks':{}}
assert result['build']['ok'],result['build']
emit,cwd=pc.emit_command(programs[0],str(compiler));r=subprocess.run([*emit,'--rc-runtime=stats'],cwd=cwd,env=pc.clean_env(),capture_output=True,check=True);declared=pc.declared_of(r.stdout)
for p in programs:
 check=pc.check(p,pc.run_spec(p,binary,'actual-llvm',declared));result['checks'][p['id']]=check
 assert check['ok'],check
 lines=[l.removeprefix('MYLANG_RC_COUNTS ') for l in check['stderr'].splitlines() if l.startswith('MYLANG_RC_COUNTS ')];assert len(lines)==1
 counts=json.loads(lines[0]);assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release']
 print(p['id'],check['svg_sha256'],flush=True)
(work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
