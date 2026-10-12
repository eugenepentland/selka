#!/usr/bin/env python3
import concurrent.futures,hashlib,json,os,pathlib,shutil,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parent;repo=root.parents[2];source=root.parent/'eda/source/src'
compiler=sys.argv[1];label=sys.argv[2]
if '--batch' in sys.argv:
 peer=pathlib.Path('/home/epentland/ai/canopy/mylang-lox-eda-20261012-eda/experiments/lox-eda-zero-rc-20261012/eda/source/src')
 for name in ['export_kicad_sch.my','export_kicad_sch_test.my']:
  shutil.copyfile(peer/name,source/name)
 modules=[source/name for name in sys.argv[4:]];assert len(modules)<=4
 def one(module):
  r=subprocess.run([compiler,'check',str(module),'--experimental-zero-rc'],capture_output=True,text=True,timeout=120)
  return {'module':module.name,'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(one,modules))
 print(json.dumps(rows));sys.exit(0)
modules=sys.argv[3:] or sorted(p.name for p in source.glob('*.my') if p.name.startswith(('export_kicad','kicad_')) and p.name not in ('export_kicad_sch.my','export_kicad_sch_test.my'))
output=root/(label+'.json');assert not output.exists();rows=[]
for offset in range(0,len(modules),4):
 r=subprocess.run([str(repo/'scripts/build-slot.sh'),'build',sys.executable,__file__,compiler,label,'--batch',*modules[offset:offset+4]],capture_output=True,text=True,check=True)
 rows.extend(json.loads(r.stdout));output.write_text(json.dumps({'compiler':compiler,'compiler_sha256':hashlib.sha256(pathlib.Path(compiler).read_bytes()).hexdigest(),'modules':rows},indent=2)+'\n')
 print(offset+len(modules[offset:offset+4]),'/',len(modules),'checks done',flush=True)
for r in rows:
 if r['status']:print(r['module'],r['stderr'].splitlines()[0])
print(sum(r['status']==0 for r in rows),'/',len(rows),'pass')
