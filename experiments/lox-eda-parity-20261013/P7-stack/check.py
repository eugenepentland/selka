#!/usr/bin/env python3
"""One outer build lease: contract probes, poisoned ASan/UBSan, counts and native memset proof."""
import pathlib,hashlib,json,subprocess,os,re
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack';work=root/'.tmp/lox-eda-parity/P7-stack';out=base/'checks-002';out.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build'
zig=pathlib.Path(os.environ['ZIG']);gcc=pathlib.Path('/usr/bin/gcc').resolve();objdump=pathlib.Path('/usr/bin/objdump').resolve();manifest=json.loads((base/'runtime-variants.json').read_text());rows=[];counts={}
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
pins={str(p):sha(p) for p in [zig,gcc,objdump,root/'src/core/runtime/core_owned_copy.c',root/'src/core/runtime/owned_copy_stack_fixture.c',base/'runtime-variants.json',pathlib.Path(__file__)]}
for p in [pathlib.Path('/usr/lib/x86_64-linux-gnu/libasan.so.8.0.0'),pathlib.Path('/usr/lib/x86_64-linux-gnu/libubsan.so.1.0.0')]:pins[str(p)]=sha(p)
def run(label,argv,want=0,extra=None):
 env={**os.environ,'MYL_CORE_LEAKCHECK':'1','MYLANG_COUNTERS':str(work/(label+'.counts.json')),'ZIG_LOCAL_CACHE_DIR':str(work/'zig-local'),'ZIG_GLOBAL_CACHE_DIR':str(work/'zig-global'),'MYLANG_JOBS':'4',**(extra or {})};r=subprocess.run(list(map(str,argv)),capture_output=True,env=env,cwd=work,timeout=120);(out/(label+'.stdout')).write_bytes(r.stdout);(out/(label+'.stderr')).write_bytes(r.stderr);rows.append({'label':label,'argv':list(map(str,argv)),'cwd':str(work),'returncode':r.returncode,'expected':want});(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==want,(label,r.returncode,r.stderr);return r
run('count-source-generator',[zig,'test',work/'generator/generate.zig','-j4'])
flags=['-target','x86_64-linux-gnu.2.31','-march=native','-mllvm','-x86-experimental-pref-innermost-loop-alignment=6']
proof={}
for variant in ['baseline','candidate']:
 folder=work/variant;assert sha(folder/'core_rt.c')==manifest['variants'][variant]['runtime_sha256'];(folder/'counted-harness.c').write_bytes((folder/'harness.c').read_bytes().replace(b'#include "core_rt.c"',b'#include "counted_rt.c"'))
 for abi,abi_flags in [('rc',[]),('zero-rc',['-DMYL_ZERO_RC=1'])]:
  label=variant+'-'+abi
  binary=folder/('probe-'+abi);run(label+'-build',[zig,'cc','-O2','-std=c11','-pthread',*abi_flags,folder/'harness.c','-lm','-o',binary]);good=run(label+'-run',[binary]);assert good.stdout==b'copy stack paths passed; live=0\n' and good.stderr==b''
  for mode in ['tag','resource','descriptor']:run(label+'-'+mode,[binary,mode],-6)
  binary=folder/('counted-'+abi);run(label+'-count-build',[zig,'cc','-O2','-std=c11','-pthread','-DP7_STACK_COUNTED=1',*abi_flags,folder/'counted-harness.c','-lm','-o',binary]);r=run(label+'-count-run',[binary]);assert r.stderr==b'';count_path=work/(label+'-count-run.counts.json');counts[label]=json.loads(count_path.read_text());assert counts[label]['totals']['live_bytes_at_exit']==0
  binary=folder/('sanitized-'+abi);run(label+'-san-build',[gcc,'-O1','-g','-std=c11','-pthread','-Wno-attributes','-fsanitize=address,undefined','-fno-omit-frame-pointer','-ftrivial-auto-var-init=pattern',*abi_flags,folder/'harness.c','-lm','-o',binary]);san_env={'ASAN_OPTIONS':'halt_on_error=1:detect_leaks=1','UBSAN_OPTIONS':'halt_on_error=1:print_stacktrace=1'};r=run(label+'-san-run',[binary],extra=san_env);assert r.stderr==b'' and r.stdout==good.stdout
  for mode in ['tag','resource','descriptor']:run(label+'-san-'+mode,[binary,mode],-6,extra=san_env)
  for mode,marker in [('asan-control',b'AddressSanitizer'),('ubsan-control',b'out of bounds')]:r=run(label+'-'+mode,[binary,mode],1,extra={**san_env, 'UBSAN_OPTIONS': 'halt_on_error=0:print_stacktrace=1'} if mode=='asan-control' else san_env);assert marker in r.stderr
 # Exact unsanitized Release runtime flags; LLVM and machine-code evidence.
 llvm=folder/'release.ll';obj=folder/'release.o';common=[zig,'cc','-O2','-g0','-falign-functions=64','-std=c11','-pthread','-DMYL_ZERO_RC=1',*flags]
 run(variant+'-llvm',[*common,'-S','-emit-llvm',folder/'core_rt.c','-o',llvm]);run(variant+'-object',[*common,'-c',folder/'core_rt.c','-o',obj]);asm=run(variant+'-disassembly',[objdump,'-dr','--disassemble=myl_core_values_copy_box',obj]).stdout
 text=llvm.read_text();body=re.search(r'define[^\n]*@myl_core_values_copy_box\([^\n]*\).*?\n}',text,re.S).group(0);(out/(variant+'.values-copy.ll')).write_text(body+'\n');(out/(variant+'.values-copy.asm')).write_bytes(asm);has1552=bool(re.search(r'llvm\.memset[^\n]*i64 1552',body));proof[variant]={'initial_1552_memset':has1552,'runtime_object_sha256':sha(obj),'llvm_sha256':sha(llvm),'native_memset_relocation':b'memset' in asm,'native_1552_immediate':b'0x610' in asm}
assert proof['baseline']['initial_1552_memset'] and not proof['candidate']['initial_1552_memset'],proof
assert proof['baseline']['native_memset_relocation'] and proof['baseline']['native_1552_immediate'],proof
for abi in ['rc','zero-rc']:assert counts['baseline-'+abi]==counts['candidate-'+abi],abi
assert all(sha(p)==h for p,h in pins.items());(out/'receipt.json').write_text(json.dumps({'status':'passed','commands':len(rows),'pins':pins,'counters':counts,'native_proof':proof,'runtime_manifest_sha256':sha(base/'runtime-variants.json'),'sanitizers':'GCC ASan+UBSan plus stack-pattern poisoning; deliberate ASan/UBSan controls mustfail','outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n');print('both variants/ABIs passed; sanitizercontrols active; counters identical; initial1552memset removed')
