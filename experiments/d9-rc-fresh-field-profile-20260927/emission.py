import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd(); work=root/'.tmp-mut-argument/tree-profile'
compiler=root.parent/'d9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang'
command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'emit-qbe',str(work/'binary_trees_n12.my'),'--rc-runtime','--drop-step-checks','--drop-frame-checks']
r=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)),check=True)
(work/'emitted.json').write_text(r.stdout); data=json.loads(r.stdout)
for f in data['functions']:
 if f['name'] in ('make','check'): (work/(f['name']+'.ssa')).write_text(f['il'])
(work/'emission-identity.json').write_text(json.dumps(dict(command=command,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),source_sha256=hashlib.sha256((work/'binary_trees_n12.my').read_bytes()).hexdigest(),functions=[dict(name=f['name'],symbol=f['symbol']) for f in data['functions']]),indent=2)+'\n')
