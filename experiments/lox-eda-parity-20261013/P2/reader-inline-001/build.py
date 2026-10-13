#!/usr/bin/env python3
"""Private LLVM-only two-reader inlining trial, exact frozen native providers."""
import hashlib,json,os,pathlib,shutil,subprocess,time
root=pathlib.Path.cwd();out=root/'experiments/lox-eda-parity-20261013/P2/reader-inline-001';work=root/'.tmp/lox-eda-parity/P2/reader-inline-001';work.mkdir(parents=True,exist_ok=True)
assert os.environ['MYLANG_ADMISSION_KIND']=='build'
coordinator=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012');p7=pathlib.Path('/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013')
compiler=coordinator/'.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang';zig=pathlib.Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig');number=coordinator/'.tmp/lox-eda-parity/coordinator/common-001/zig-cache/o/38d22d1e4461e413e446fb42adf284b2/core_number_text.o';runtime=p7/'.tmp/lox-eda-parity/P7-runtime/guests/baseline.o';llvm=root/'.tmp/lox-eda-parity/P2/scalar-ip-001/candidate.ll';original=root/'.tmp/lox-eda-parity/P2/scalar-ip-001/candidate'
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
pins={str(compiler):'955f311e1dbf65b55f4c148ab03cdcb4881bc5668289aea93336dbfd7985206a',str(zig):'1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f',str(number):'7319abd678df56df66f7913ead6715206cb1aa964d42428a6eee7def9bb7b4c5',str(runtime):'a1dd63bd451e8c7b7ebb9e7bbaf744e214f8055b90b184eaa7b26aa792575885',str(llvm):'794a1cbe5824a7e524eb92dc24bbff2ef9a284dc8af85f830b37432c71681a9e',str(original):'c98e80fddbcc78f6c8f94cfa4b97f392d4ef938b9befd1b92a7e8ac11360cd92'}
for path,h in pins.items():assert sha(path)==h,(path,sha(path),h)
flags=['-target','x86_64-linux-gnu.2.31','-march=native','-mllvm','-x86-experimental-pref-innermost-loop-alignment=6'];rows=[]
env={**os.environ,'ZIG_LOCAL_CACHE_DIR':str(work/'zig-local'),'ZIG_GLOBAL_CACHE_DIR':str(work/'zig-global'),'TMPDIR':str(work/'tmp'),'MYLANG_JOBS':'4'};pathlib.Path(env['TMPDIR']).mkdir(exist_ok=True)
for k in ['MYLANG_COUNTERS','MYL_CORE_LEAKCHECK']:env.pop(k,None)
def run(name,argv):
 assert all(sha(p)==h for p,h in pins.items())
 begin=time.perf_counter();r=subprocess.run(list(map(str,argv)),capture_output=True,env=env,timeout=120);rows.append({'name':name,'argv':list(map(str,argv)),'status':r.returncode,'build_diagnostic_wall_seconds':time.perf_counter()-begin});(out/(name+'.stdout')).write_bytes(r.stdout);(out/(name+'.stderr')).write_bytes(r.stderr);(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==0,(name,r.stderr)
def inline(source,names):
 lines=source.splitlines(keepends=True);count=0
 for i,line in enumerate(lines):
  if line.startswith('define ') and any('@"'+n+'"(' in line for n in names):
   assert 'alwaysinline' not in line and 'noinline' not in line;lines[i]=line.replace(' nounwind ', ' alwaysinline nounwind ',1);count+=1
 assert count==len(names),(count,names)
 altered=''.join(lines)
 restored=altered.splitlines(keepends=True)
 for i,line in enumerate(restored):
  if line.startswith('define ') and any('@\"'+n+'\"(' in line for n in names):restored[i]=line.replace(' alwaysinline nounwind ',' nounwind ',1)
 assert ''.join(restored)==source
 return altered
private_runtime=work/'runtime.o';private_number=work/'number.o';shutil.copyfile(runtime,private_runtime);shutil.copyfile(number,private_number)
binaries={}
for arm in ['baseline','inline']:
 ll=work/(arm+'.ll');ll.write_text(llvm.read_text() if arm=='baseline' else inline(llvm.read_text(),['my.vm::read_byte','my.vm::read_constant']));obj=work/(arm+'.o');binary=work/arm
 run(arm+'-compile',[zig,'cc','-c','-O3',*flags,'-Wno-override-module','-o',obj,ll]);run(arm+'-link',[zig,'cc','-O3',*flags,'-pthread','-Wno-override-module','-o',binary,obj,private_runtime,private_number,'-lm']);binaries[arm]={'path':str(binary),'sha256':sha(binary),'llvm_sha256':sha(ll),'object_sha256':sha(obj)}
 for tool,args in [('nm',['-S','--size-sort']),('size',['-A']),('objdump',['-d'])]:
  r=subprocess.run([tool,*args,str(binary)],capture_output=True,check=True);(out/(arm+'.'+tool+'.txt')).write_bytes(r.stdout)
probe_source=root/'.tmp/lox-eda-parity/P2/scalar-ip-001/probe-source/main.my';pins[str(probe_source)]=sha(probe_source)
run('probe-emit',[compiler,'build',probe_source,'--release','--experimental-zero-rc','--cache-dir',work/'probe-cache','--emit-llvm',work/'probe-base.ll','-o',work/'probe-base'])
ll=work/'probe-inline.ll';ll.write_text(inline((work/'probe-base.ll').read_text(),['my.main::scalar_read_byte','my.main::scalar_read_constant']));obj=work/'probe-inline.o'
run('probe-inline-compile',[zig,'cc','-c','-O3',*flags,'-Wno-override-module','-o',obj,ll]);run('probe-inline-link',[zig,'cc','-O3',*flags,'-pthread','-Wno-override-module','-o',work/'probe-inline',obj,private_runtime,private_number,'-lm'])
run('baseline-cli',["python3",root/'experiments/lox-eda-improvements-20261012/P1/verify.py',work/'baseline',original,out/'baseline-cli','--correctness-only'])
run('inline-cli',["python3",root/'experiments/lox-eda-improvements-20261012/P1/verify.py',work/'inline',work/'baseline',out/'inline-cli','--correctness-only'])
run('inline-fatal',["python3",root/'experiments/lox-eda-parity-20261013/P2/scalar-ip-001/verify_fatal.py',work/'probe-inline',out/'inline-fatal'])
(out/'receipt.json').write_text(json.dumps({'status':'qualified_not_timed','inputs':pins,'harness_sha256':sha(__file__),'native_flags':flags,'binaries':binaries,'runtime_private_sha256':sha(private_runtime),'number_private_sha256':sha(private_number),'outer_admission':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n');print('private baseline/inline relinks and CLI/fatal controls qualified')
