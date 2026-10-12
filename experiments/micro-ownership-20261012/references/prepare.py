#!/usr/bin/env python3
"""Build fresh foreign ports and qualify only; no performance sample collection."""
import hashlib, importlib.util, json, os, pathlib, re, shutil, subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
OUT=pathlib.Path(__file__).resolve().parent
WORK=ROOT/'.tmp/micro-ownership/references'
BASE='e303d704d37d9cbd90c643ce4f06a4ecb9895718'
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def write(name,data): (OUT/name).write_text(json.dumps(data,indent=2)+'\n')
WORK.mkdir(parents=True,exist_ok=True)
for name in ('tmp','gocache','zigcache','zig-global-cache','cargo-target','bin'): (WORK/name).mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('registry', ROOT/'benchmarks/runtime/expanded/registry.py'); reg=importlib.util.module_from_spec(spec); spec.loader.exec_module(reg)
env=dict(os.environ)
for key in list(env):
 if key.startswith('MYLANG_') or key in ('GODEBUG','RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS','CARGO_BUILD_RUSTFLAGS','RUSTC_WRAPPER','RUSTC_WORKSPACE_WRAPPER','CARGO_PROFILE_RELEASE_OPT_LEVEL','CARGO_PROFILE_RELEASE_LTO','CARGO_PROFILE_RELEASE_CODEGEN_UNITS','CARGO_BUILD_TARGET','RUSTC_BOOTSTRAP','CFLAGS','CXXFLAGS','CGO_CFLAGS','CGO_CPPFLAGS','CGO_CXXFLAGS','CGO_LDFLAGS','LDFLAGS'): env.pop(key,None)
env.update(GOMAXPROCS='1',GOGC='100',GOMEMLIMIT='off',GOAMD64='v1',GOFLAGS='',GOEXPERIMENT='',GOTOOLCHAIN='local',MYLANG_SLOT_DIR='/home/epentland/.cache/mylang/slots',MYLANG_DEV_JOBS='4',MYLANG_DEV_MAXRSS='8589934592',MYLANG_BUILD_MEM='8G',MYLANG_BUILD_SLOTS='3',TMPDIR=str(WORK/'tmp'),GOCACHE=str(WORK/'gocache'),ZIG_LOCAL_CACHE_DIR=str(WORK/'zigcache'),ZIG_GLOBAL_CACHE_DIR=str(WORK/'zig-global-cache'))
paths={'rust':shutil.which('rustc') or '/home/epentland/.cargo/bin/rustc','cargo':shutil.which('cargo') or '/home/epentland/.cargo/bin/cargo','go':shutil.which('go'),'zig':os.environ['ZIG']}
tools={}
for key,path in paths.items():
 probe=subprocess.run([path,'version' if key in ('go','zig') else '--version'],capture_output=True,text=True,check=True,env=env)
 actual=pathlib.Path(path).resolve()
 if key=='rust': actual=pathlib.Path(subprocess.check_output([path,'--print','sysroot'],env=env,text=True).strip())/'bin/rustc'
 if key=='cargo': actual=pathlib.Path(subprocess.check_output([str(pathlib.Path(path).resolve()),'which','cargo'],env=env,text=True).strip()) if pathlib.Path(path).resolve().name=='rustup' else actual
 tools[key]={'path':path,'actual_path':str(actual),'invocation_sha256':sha(path),'sha256':sha(actual),'version':probe.stdout.strip()}
env['RUSTC']=paths['rust']
sources={}; commands={}; results={}
for group in reg.GROUPS:
 src=ROOT/('benchmarks/runtime/ports' if group=='legacy' else 'benchmarks/runtime/expanded/'+group)
 dest=OUT/'sources'/group; dest.mkdir(parents=True,exist_ok=True)
 for name in ('main.rs','main.go','main.zig',*(['Cargo.toml','Cargo.lock'] if group=='text' else [])):
  original=src/name; copy=dest/name
  if not copy.exists(): shutil.copy2(original,copy)
  sources[str(copy.relative_to(ROOT))]={'canonical':str(original.relative_to(ROOT)),'canonical_sha256':sha(original),'sha256':sha(copy)}
 for arm in ('rust','go','zig-safe','zig-fast'):
  key=group+'/'+arm; binary=WORK/'bin'/f'{group}-{arm}'
  if arm=='rust': cmd=[paths['rust'],'-O','--edition','2021',str(dest/'main.rs'),'-o',str(binary)]
  elif arm=='go': cmd=[paths['go'],'build','-o',str(binary),str(dest/'main.go')]
  else: cmd=[paths['zig'],'build-exe',str(dest/'main.zig'),'-lc','-O','ReleaseSafe' if arm=='zig-safe' else 'ReleaseFast','-femit-bin='+str(binary)]
  if group=='text' and arm=='rust': cmd=[paths['cargo'],'build','--release','--locked','--manifest-path',str(dest/'Cargo.toml'),'--target-dir',str(WORK/'cargo-target')]
  command=[str(ROOT/'scripts/build-slot.sh'),'build',*cmd]; commands[key]=command
  done=subprocess.run(command,env=env,capture_output=True,text=True)
  log=OUT/'logs'/f'{group}-{arm}.log'; log.parent.mkdir(exist_ok=True); log.write_text(done.stdout+done.stderr)
  results[key]={'exit_status':done.returncode,'log':str(log.relative_to(ROOT)),'log_sha256':sha(log)}
  if done.returncode==0:
   if group=='text' and arm=='rust': shutil.copy2(WORK/'cargo-target/release/runtime_text',binary)
   binary.chmod(0o555); results[key].update(path=str(binary),sha256=sha(binary))
  print(key,done.returncode,flush=True)
write('manifest.json',{'schema':'micro-foreign-reference-build-v1','base_revision':BASE,'migration_edits':[],'oracle_source_hashes':{str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'benchmarks/runtime/oracle.py',ROOT/'benchmarks/runtime/expanded/registry.py',*[ROOT/'benchmarks/runtime/expanded'/g/'oracle.py' for g in ('compute','collections','text')]]},'source_root':str(ROOT),'fresh_build':True,'tools':tools,'sources':sources,'commands':commands,'environment':{k:env[k] for k in ('GOMAXPROCS','GOGC','GOMEMLIMIT','GOAMD64','GOFLAGS','GOEXPERIMENT','GOTOOLCHAIN','MYLANG_SLOT_DIR','MYLANG_DEV_JOBS','MYLANG_DEV_MAXRSS','TMPDIR','GOCACHE','ZIG_LOCAL_CACHE_DIR','ZIG_GLOBAL_CACHE_DIR','RUSTC')},'builds':results,'entries':[{'group':key.split('/')[0],'arm':key.split('/')[1],'kind':'runtime','binary':item.get('path'),'sha256':item.get('sha256'),'status':'built' if item['exit_status']==0 else 'unavailable','source':str(OUT/'sources'/key.split('/')[0]/('main.rs' if key.endswith('/rust') else 'main.go' if key.endswith('/go') else 'main.zig')),'flags':commands[key][2:],'diagnostic':item['log']} for key,item in results.items()]})
command=[str(ROOT/'scripts/build-slot.sh'),'build','python3',str(OUT/'qualify.py')]
m=json.loads((OUT/'manifest.json').read_text()); m['qualification_admission_command']=command; write('manifest.json',m)
done=subprocess.run(command,env=env,capture_output=True,text=True); (OUT/'qualification-admission.log').write_text(done.stdout+done.stderr); done.check_returncode()
