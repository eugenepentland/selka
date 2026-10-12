#!/usr/bin/env python3
"""Paired source admission for additional existing Core/CLI fixture roots."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
p=argparse.ArgumentParser()
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--cache',type=Path,required=True)
p.add_argument('--start',type=int,default=0)
p.add_argument('--limit',type=int,default=10)
a=p.parse_args()
compiler=a.compiler.resolve()
sources=sorted([*Path('test/core').rglob('*.my'),*Path('test/fixtures').rglob('*.my')])
rows=[]
started=time.monotonic()
for source in sources[a.start:a.start+a.limit]:
    row=dict(source=str(source),sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    for label,flags in [('ordinary',[]),('zero_rc',['--experimental-zero-rc'])]:
        cmd=[str(compiler),'check',str(source.resolve()),'--cache-dir',str(a.cache.resolve()),*flags]
        r=subprocess.run(cmd,capture_output=True,text=True)
        row[label]=dict(argv=cmd,status=r.returncode,stdout=r.stdout,stderr=r.stderr)
    rows.append(row)
result=dict(compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
            total_denominator=len(sources),start=a.start,limit=a.limit,seconds=time.monotonic()-started,results=rows)
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'checked':len(rows),'seconds':result['seconds'],'new_refusals':sum(x['ordinary']['status']==0 and x['zero_rc']['status']!=0 for x in rows)}),flush=True)
