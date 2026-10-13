#!/usr/bin/env python3
"""Relink one frozen C1 LLVM object against isolated runtime variants; no timing."""
import pathlib,hashlib,json,os,subprocess,shutil
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-runtime';work=root/'.tmp/lox-eda-parity/P7-runtime';out=base/'guest-builds-001';out.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build'
coordinator=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012');llvm=coordinator/'.tmp/lox-eda-parity/P6/native-001/eda/zero-rc.ll';control=coordinator/'.tmp/lox-eda-parity/P6/native-001/eda/zero-rc';compiler=coordinator/'.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang';number=coordinator/'.tmp/lox-eda-parity/coordinator/common-001/zig-cache/o/38d22d1e4461e413e446fb42adf284b2/core_number_text.o';zig=pathlib.Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
assert sha(llvm)=='74599602ae7e9607ce8a34de65b5f825520ee7f41190b385d813dd9b16e9024f';assert sha(compiler)=='955f311e1dbf65b55f4c148ab03cdcb4881bc5668289aea93336dbfd7985206a';assert sha(number)=='7319abd678df56df66f7913ead6715206cb1aa964d42428a6eee7def9bb7b4c5'
pins={str(p):sha(p) for p in [llvm,control,compiler,number,zig]};receipts=json.loads((coordinator/'experiments/lox-eda-parity-20261013/coordinator/common-001/build-receipt.json').read_text());install=compiler.parents[1]
for record in receipts['installation_files']:pins[str(install/record['path'])]=record['sha256']
variant_manifest=json.loads((base/'runtime-variants-002.json').read_text());build=work/'guests';build.mkdir();private_llvm=build/'C1.ll';private_number=build/'C1-number.o';shutil.copyfile(llvm,private_llvm);shutil.copyfile(number,private_number)
flags=['-target','x86_64-linux-gnu.2.31','-march=native','-mllvm','-x86-experimental-pref-innermost-loop-alignment=6'];rows=[]
def run(name,argv):
 assert all(sha(p)==h for p,h in pins.items())
 env={**os.environ,'ZIG_LOCAL_CACHE_DIR':str(work/'zig-local'),'ZIG_GLOBAL_CACHE_DIR':str(work/'zig-global'),'MYLANG_JOBS':'4'};env.pop('MYLANG_COUNTERS',None);env.pop('MYL_CORE_LEAKCHECK',None)
 r=subprocess.run(list(map(str,argv)),capture_output=True,env=env,cwd=root,timeout=120)
 (out/(name+'.stdout')).write_bytes(r.stdout);(out/(name+'.stderr')).write_bytes(r.stderr);rows.append({'name':name,'argv':list(map(str,argv)),'returncode':r.returncode});(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==0,(name,r.stderr)
obj=build/'C1.o';run('llvm-object',[zig,'cc','-c','-O3',*flags,'-Wno-override-module','-o',obj,private_llvm]);binaries={}
for variant in ['baseline','scalar','pointer','combined','bulk','all']:
 folder=work/'002'/variant;source=folder/'runtime.c';assert sha(source)==variant_manifest['variants'][variant]['runtime_sha256'];runtime=build/(variant+'.c');runtime.write_bytes(b'#define MYL_ZERO_RC 1\n'+source.read_bytes());runtime_obj=build/(variant+'.o');binary=build/('eda-'+variant)
 run(variant+'-runtime',[zig,'cc','-c','-O2','-g0','-falign-functions=64',*flags,'-std=c11','-pthread','-o',runtime_obj,runtime])
 run(variant+'-link',[zig,'cc','-O3',*flags,'-pthread','-Wno-override-module','-o',binary,obj,runtime_obj,private_number,'-lm'])
 symbols=subprocess.run(['nm','--defined-only',str(binary)],capture_output=True,check=True);(out/(variant+'.symbols')).write_bytes(symbols.stdout);assert not any(token in symbols.stdout for token in [b'myl_core_retain',b'myl_core_release',b'myl_core_share'])
 binaries[variant]={'path':str(binary),'sha256':sha(binary),'runtime_source_sha256':sha(runtime),'runtime_object_sha256':sha(runtime_obj),'symbol_sha256':sha(out/(variant+'.symbols'))}
assert all(sha(p)==h for p,h in pins.items())
(out/'build-receipt.json').write_text(json.dumps({'status':'built_not_timed','inputs':pins,'installation_receipt_sha256':sha(coordinator/'experiments/lox-eda-parity-20261013/coordinator/common-001/build-receipt.json'),'llvm_object_sha256':sha(obj),'private_llvm_sha256':sha(private_llvm),'private_number_sha256':sha(private_number),'variants':binaries,'native_flags':flags,'harness_sha256':sha(__file__),'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n')
print('six frozen-LLVM guest relinks built; no timing run')
