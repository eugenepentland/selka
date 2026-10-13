#!/usr/bin/env python3
"""One admitted diagnostic lease for sibling transfer pairing on frozen helper."""
import hashlib,json,os,pathlib,shutil,subprocess
P=pathlib.Path;root=P(__file__).resolve().parents[3];out=root/'experiments/lox-eda-parity-20261013/P7/sibling-audit-002';work=root/'.tmp/lox-eda-parity/P7/sibling-audit-002'
assert os.environ.get('MYLANG_ADMISSION_KIND')=='build';out.mkdir();work.mkdir()
compiler=root/'.tmp/lox-eda-parity/P7/green-install-002/bin/mylang';rows=[]
for fixture in ['sibling-overwrite','sibling-overwrite-zero']:
 source=P('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p3/experiments/lox-eda-parity-20261013/P3/exchange-review')/(fixture+'.my');copy=work/source.name;shutil.copyfile(source,copy)
 for mode,flags in [('zero-rc',['--experimental-zero-rc']),('rc',[])]:
  binary=work/(fixture+'-'+mode);argv=[str(compiler),'build',str(copy),'--release','--counters',*flags,'--cache-dir',str(work/('cache-'+fixture+'-'+mode)),'--emit-llvm',str(binary)+'.ll','-o',str(binary)]
  env={**os.environ,'MYLANG_JOBS':'4'};env.pop('MYLANG_COUNTERS',None);env.pop('MYL_CORE_LEAKCHECK',None)
  r=subprocess.run(argv,cwd=root,env=env,capture_output=True);name=fixture+'-'+mode+'-build';(out/(name+'.stderr')).write_bytes(r.stderr);rows.append({'name':name,'argv':argv,'returncode':r.returncode,'source_sha256':hashlib.sha256(copy.read_bytes()).hexdigest()})
  if r.returncode:continue
  for args in [[],['take']]:
   name=fixture+'-'+mode+('-take' if args else '-overwrite');counts=out/(name+'.counters.json');argv=[str(binary),*args];r=subprocess.run(argv,env={**env,'MYLANG_COUNTERS':str(counts),'MYL_CORE_LEAKCHECK':'1'},capture_output=True);(out/(name+'.stdout')).write_bytes(r.stdout);(out/(name+'.stderr')).write_bytes(r.stderr);rows.append({'name':name,'argv':argv,'returncode':r.returncode,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'counters':json.loads(counts.read_text()) if counts.exists() else None})
(out/'results.json').write_text(json.dumps({'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'outer_lease':os.environ['MYLANG_ADMISSION_KIND'],'rows':rows},indent=2)+'\n')
