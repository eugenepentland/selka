#!/usr/bin/env python3
"""One outer build lease; native ABI checks, no timing experiment."""
import pathlib,subprocess,json,os,hashlib,re
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-runtime';work=root/'.tmp/lox-eda-parity/P7-runtime';out=base/'probes-001';out.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build'
zig=pathlib.Path(os.environ.get('MYLANG_ZIG','/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'))
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
source_pins={str(p):sha(p) for p in (root/'src/core/runtime').glob('*') if p.is_file()}
manifest=json.loads((base/'runtime-variants.json').read_text());rows=[];results={}
def run(name,argv,expected=0):
 env={**os.environ,'ZIG_LOCAL_CACHE_DIR':str(work/'zig-local'),'ZIG_GLOBAL_CACHE_DIR':str(work/'zig-global'),'MYLANG_JOBS':'4','MYL_CORE_LEAKCHECK':'1'};env.pop('MYLANG_COUNTERS',None)
 r=subprocess.run(list(map(str,argv)),capture_output=True,cwd=root,env=env,timeout=120)
 (out/(name+'.stdout')).write_bytes(r.stdout);(out/(name+'.stderr')).write_bytes(r.stderr);rows.append({'name':name,'argv':list(map(str,argv)),'returncode':r.returncode,'expected':expected});(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==expected,(name,r.stderr);return r
for variant in ['baseline','scalar','pointer','combined']:
 folder=work/variant
 assert sha(folder/'runtime.c')==manifest['variants'][variant]['runtime_sha256']
 assert sha(folder/'probe-runtime.c')==manifest['variants'][variant]['probe_runtime_sha256']
 for abi,flags in [('rc',[]),('zero-rc',['-DMYL_ZERO_RC=1'])]:
  name=variant+'-'+abi;binary=folder/('probe-'+abi)
  run(name+'-build',[zig,'cc','-O2','-g0','-falign-functions=64','-std=c11','-target','x86_64-linux-gnu.2.31','-march=native','-pthread',*flags,folder/'probe.c','-lm','-o',binary])
  r=run(name+'-run',[binary]);assert r.stderr==b'' and r.stdout.endswith(b'runtime contracts passed; live=0\n')
  results[name]={'values':dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',r.stdout.decode())),'binary_sha256':sha(binary)}
  for invalid in ['tag','resource','descriptor']:run(name+'-'+invalid,[binary,invalid],-6)
for abi in ['rc','zero-rc']:
 old=results['baseline-'+abi]['values']
 for variant in ['scalar','pointer','combined']:
  new=results[variant+'-'+abi]['values'];assert new['copy_blocks']==old['copy_blocks']==4
  assert new['copy_pushes']==(10 if variant in ['scalar','combined'] else 400)
  if abi=='zero-rc' and variant in ['pointer','combined']:assert new['pointer_references']==1 and new['recursive_references']==0
  else:assert new['pointer_references']==7 and new['recursive_references']==40000
assert all(sha(p)==h for p,h in source_pins.items())
(out/'results.json').write_text(json.dumps({'status':'passed','variants':results,'source_pins':source_pins,'runtime_manifest_sha256':sha(base/'runtime-variants.json'),'probe_sha256':sha(base/'probe.c'),'harness_sha256':sha(__file__),'zig':str(zig),'zig_sha256':sha(zig),'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']},'commands':len(rows)},indent=2)+'\n')
print('eight ABI/variant cells passed;40 native commands; no timing measured')
