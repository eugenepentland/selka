import hashlib,json,os,subprocess
from pathlib import Path
here=Path(__file__).resolve().parent;out=Path.cwd()/'.tmp/memory-closeout/A02/field-augmented-prior-mut';out.mkdir(parents=True,exist_ok=False)
compiler=Path.cwd()/'.zig-cache/o/75e409ad69f15be3d392595458eae627/mylang';baseline=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang')
r={'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'cases':{}}
for name in ['augmented','method']:
 source=here/(name+'.my');r['cases'][name]={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
 for label,argv in [('raw',[compiler,'dump-ir',source,'--experimental-zero-rc']),('facts',[compiler,'dump-ir',source,'--experimental-zero-rc','--facts']),('build',[compiler,'build',source,'--experimental-zero-rc','--release','--cache-dir',out/(name+'-cache'),'-o',out/name])]+([('baseline',[baseline,'build',source,'--experimental-zero-rc','--release','--cache-dir',out/'baseline-cache','-o',out/'baseline'])] if name=='method' else []):
  argv=list(map(str,argv));p=subprocess.run(argv,capture_output=True,text=True,timeout=90);r['cases'][name][label]={'argv':argv,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};(here/(name+'-'+label+'.txt')).write_text(p.stdout+p.stderr);(here/'results.json').write_text(json.dumps(r,indent=2)+'\n');print(name,label,p.returncode,flush=True)
