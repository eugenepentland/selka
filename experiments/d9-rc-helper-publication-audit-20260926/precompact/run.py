import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp/semantic-history-audit/precompact';compiler=root/'.tmp/compact-journal/before/bin/mylang'
record={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'source_commit':'c31666341191f490caba5fb9b172320d0aea5509','runs':{}}
for backend in ('qbe',):
 for source in sorted(work.glob('*.my')):
  for runtime in ('gc','rc'):
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(source),'--cache-dir='+str(work/'cache')]+(['--release'] if backend=='llvm' else [])+(['--rc-runtime=stats'] if runtime=='rc' else [])
   p=subprocess.run(command,capture_output=True,text=True,env=dict(os.environ,TMPDIR=str(root/'.tmp')),timeout=600)
   key=backend+'/'+runtime+'/'+source.stem;record['runs'][key]={'command':command,'source':source.read_text(),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (work/'results.json').write_text(json.dumps(record,indent=2)+'\n');print(key,p.returncode,repr(p.stdout),flush=True)
