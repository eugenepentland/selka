"""Capture sharing-history observations without treating ABI2 parity as acceptance."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();compiler=a.compiler.resolve();rows=[]
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  for name in ('history','history_oracle'):
   source=HERE/(name+'.my');cmd=[str(compiler),'build',str(source),'--run']+(['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress'])+(['--release'] if backend=='llvm' else [])
   run=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True,timeout=300)
   rows.append({'backend':backend,'runtime':mode,'name':name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'command':cmd,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr});a.output.write_text(json.dumps(rows,indent=2)+'\n');assert run.returncode==0,rows[-1]
   print(backend,mode,name,repr(run.stdout),flush=True)
