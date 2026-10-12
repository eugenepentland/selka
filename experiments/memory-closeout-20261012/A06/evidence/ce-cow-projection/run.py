from pathlib import Path
import gzip,hashlib,json,os,subprocess,time
root=Path(__file__).resolve().parent
workspace=root.parents[3]
compiler=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support5-install/bin/mylang')
(root/'before.my').write_bytes(gzip.decompress((workspace/'experiments/memory-closeout-20261012/A06/evidence/ce-cow-projection/before.my.gz').read_bytes()))
(root/'after.my').write_bytes((workspace/'test/core/ce_cow.my').read_bytes())
report=dict(compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),source_revision='a1f19edf255c8c0886731d8d7cce450d5f657720',zig_sha256=hashlib.sha256(Path(os.environ['ZIG']).read_bytes()).hexdigest(),harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),scope='Same-compiler counted source-migration comparison; no uninstrumented runtime/RSS claim.',cases={})
expected='30115815 20000 1500 1000 1 4 0\n5 1009 5 9\n2 2 1 0\n'
def call(name,argv,env=None):
 t=time.monotonic();p=subprocess.run(list(map(str,argv)),env=env,capture_output=True,text=True,timeout=120)
 row=dict(argv=list(map(str,argv)),status=p.returncode,stdout=p.stdout,stderr=p.stderr,elapsed_s=time.monotonic()-t)
 (root/(name+'.json')).write_text(json.dumps(row,indent=2)+'\n')
 print(name,p.returncode,repr(p.stdout),repr(p.stderr[:500]),flush=True)
 return row
for name in ('before','after'):
 source=root/(name+'.my');out=root/name;counts=root/(name+'-counts.json')
 row=report['cases'][name]=dict(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
 row['build']=call(name+'-build',[compiler,'build',source,'--zig',os.environ['ZIG'],'--cache-dir',root.parent/'support5-migration-native-ce2/cache','--release','--experimental-zero-rc','--counters','-o',out,'--emit-llvm',str(out)+'.ll'])
 if row['build']['status']==0:
  row['run']=call(name+'-run',[out],dict(os.environ,MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1'))
  row['output_correct']=row['run']['status']==0 and row['run']['stdout']==expected and not row['run']['stderr']
  row['binary_sha256']=hashlib.sha256(out.read_bytes()).hexdigest()
  llvm=Path(str(out)+'.ll')
  row['llvm_sha256']=hashlib.sha256(llvm.read_bytes()).hexdigest()
  symbols=subprocess.check_output(['nm',str(out)],text=True)
  row['selected_structural_rc_free']='mylang-zero-rc-v2' in llvm.read_text() and not any(word in symbols for word in ['myl_core_retain','myl_core_release','myl_core_share','count_retain','count_release','count_is_unique'])
  if counts.exists():row['totals']=json.loads(counts.read_text())['totals']
 (root/'results.json').write_text(json.dumps(report,indent=2)+'\n')
