import hashlib,json,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parent
compiler=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang')
result={'compiler_source':'bed11cf3bf3102ffec44487e431a1573fdf02ad5','compiler_path':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'cases':{}}
for source in sorted((root/'sources').glob('*.my')):
 row={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
 for label,args in [('check',['check',str(source),'--experimental-zero-rc']),('typed',['dump-typed',str(source),'test_augmented_field_detaches_an_owned_edge_from_a_private_capture' if source.stem=='publication' else 'main'])]:
  argv=[str(compiler),*args];start=time.monotonic();p=subprocess.run(argv,capture_output=True,text=True,timeout=20)
  row[label]={'argv':argv,'status':p.returncode,'elapsed_admitted_seconds':time.monotonic()-start,'stdout':p.stdout,'stderr':p.stderr}
  if label=='typed':(root/(source.stem+'.typed')).write_text(p.stdout)
 result['cases'][source.stem]=row
(root/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print({k:v['check']['status'] for k,v in result['cases'].items()})
