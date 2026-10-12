#!/usr/bin/env python3
"""Copy exact reference executables and create specs that use the frozen copies."""
import argparse,hashlib,json,os,pathlib,shutil
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-specs',type=pathlib.Path,default=pathlib.Path(__file__).with_name('specs'))
p.add_argument('--output-specs',type=pathlib.Path,required=True)
p.add_argument('--binaries',type=pathlib.Path,required=True)
p.add_argument('--manifest',type=pathlib.Path,required=True)
a=p.parse_args();a.output_specs.mkdir(parents=True,exist_ok=False);a.binaries.mkdir(parents=True,exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rows={};count=0
for path in sorted(a.source_specs.glob('*.json')):
 spec=json.loads(path.read_text());app=spec['cell'].split('/')[0]
 for name,argv in spec['arms'].items():
  src=pathlib.Path(argv[0]);key=app+'/'+name;digest=sha(src)
  if key not in rows:
   dest=(a.binaries/(app+'-'+name)).resolve();shutil.copy2(src,dest);dest.chmod(0o555)
   assert sha(dest)==digest and os.access(dest,os.X_OK)
   rows[key]={'source':str(src),'frozen':str(dest),'sha256':digest,'bytes':dest.stat().st_size}
  assert rows[key]['source']==str(src) and rows[key]['sha256']==digest
  argv[0]=rows[key]['frozen']
 # Hash the text oracle as well as workload input files.
 if spec.get('expected_stdout'):spec['files']=sorted(set(spec.get('files',[]))|{spec['expected_stdout']})
 (a.output_specs/path.name).write_text(json.dumps(spec,indent=2)+'\n');count+=1
assert len(rows)==8 and count==61
manifest={'reference_binary_count':len(rows),'spec_count':count,'binaries':rows,'notes':['Exact existing reference artifacts freshly copied; not rebuilt.','Historical executable identity can differ; see historical provenance.','60 main comparison cells plus separately identified VM step case.']}
a.manifest.write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'reference_binaries':len(rows),'specs':count,'bytes':sum(r['bytes'] for r in rows.values())}))
