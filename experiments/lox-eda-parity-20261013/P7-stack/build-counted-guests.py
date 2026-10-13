#!/usr/bin/env python3
import pathlib,json,hashlib,subprocess,os
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack';work=root/'.tmp/lox-eda-parity/P7-stack';out=base/'counted-guests-001';out.mkdir();build=work/'counted-guests';build.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build'
co=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012');old=json.loads((base/'guest-builds-001/receipt.json').read_text());pins=dict(old['inputs']);zig=pathlib.Path(os.environ['ZIG']);common=json.loads((co/'experiments/lox-eda-parity-20261013/coordinator/common-002/build-receipt.json').read_text());compiler=pathlib.Path(common['compiler']);provider=work/'guests/C2-number.o';flags=old['native_flags'];rows=[];variants={}
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
pins[str(pathlib.Path(__file__))]=sha(__file__)
for app in ['lox','eda']:
 receipt=co/'experiments/lox-eda-parity-20261013/attempts/native-002/build'/app/'build-receipt.json';d=json.loads(receipt.read_text());pins[str(receipt)]=sha(receipt)
 for p in (co/'experiments/lox-eda-parity-20261013/source-002'/app).rglob('*.my'):pins[str(p)]=sha(p)
 for p in [work/'baseline/counted_rt.c',work/'candidate/counted_rt.c',provider]:pins[str(p)]=sha(p)
def run(label,args):
 assert all(sha(p)==h for p,h in pins.items());env={**os.environ,'ZIG_LOCAL_CACHE_DIR':str(work/'zig-local'),'ZIG_GLOBAL_CACHE_DIR':str(work/'zig-global'),'MYLANG_JOBS':'4','MYLANG_COMPONENT_DIR':str(pathlib.Path(common['installation'])/'libexec/mylang'),'MYLANG_COUNTERS':str(build/(label+'.counts.json'))};r=subprocess.run(list(map(str,args)),cwd=build,env=env,capture_output=True,timeout=300);(out/(label+'.stdout')).write_bytes(r.stdout);(out/(label+'.stderr')).write_bytes(r.stderr);rows.append({'label':label,'argv':list(map(str,args)),'cwd':str(build),'returncode':r.returncode});(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==0,(label,r.stderr);print(label,flush=True)
for variant in ['baseline','candidate']:
 run(variant+'-runtime',[zig,'cc','-c','-O2','-g0','-falign-functions=64','-std=c11','-pthread','-DMYL_ZERO_RC=1',*flags,work/variant/'counted_rt.c','-o',build/(variant+'.o')])
for app in ['lox','eda']:
 llvm=build/(app+'.ll');control=build/(app+'-C2-control');run(app+'-emit',[compiler,'build',co/'experiments/lox-eda-parity-20261013/source-002'/app/'main.my','--release','--experimental-zero-rc','--counters','--cache-dir',build/(app+'-cache'),'--emit-llvm',llvm,'-o',control]);obj=build/(app+'.o');run(app+'-llvm',[zig,'cc','-c','-O3',*flags,'-Wno-override-module',llvm,'-o',obj]);variants[app]={'control':{'path':str(control),'sha256':sha(control)}}
 for variant in ['baseline','candidate']:
  binary=build/(app+'-'+variant);run(app+'-'+variant,[zig,'cc','-O3',*flags,'-pthread','-Wno-override-module',obj,build/(variant+'.o'),provider,'-lm','-o',binary]);variants[app][variant]={'path':str(binary),'sha256':sha(binary)}
 for p in [llvm,obj]:pins[str(p)]=sha(p)
assert all(sha(p)==h for p,h in pins.items());(out/'receipt.json').write_text(json.dumps({'status':'built_untimed','inputs':pins,'variants':variants,'commands':rows,'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n')
for app in variants:
 for item in variants[app].values():p=pathlib.Path(item['path']);p.chmod(p.stat().st_mode&~0o222)
