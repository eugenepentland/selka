#!/usr/bin/env python3
"""Verify iteration traps and snapshot boundaries on both runtimes and backends."""
from pathlib import Path
import argparse
import json
import subprocess
import hashlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--work', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler = args.compiler.resolve()
cases={
 'dict':('def main() -> int:\n    values = {1: 10}\n    for key in values:\n        values[2] = key\n    return 0\n',1),
 'set':('def main() -> int:\n    values = {1, 2}\n    for key in values:\n        values.add(key + 10)\n    return 0\n',1),
 'list':('def main() -> int:\n    values = [1]\n    for value in values:\n        values.append(value)\n    return 0\n',1),
 'pinned':('def grow(values: mut list[int]) -> int:\n    for value in values:\n        values.append(value)\n        continue\n    return 0\ndef main() -> int:\n    values = [1]\n    return grow(mut values)\n',1),
 'reverse':('def main() -> int:\n    values = [1]\n    for value in reversed(values):\n        values.append(value)\n    return 0\n',1),
 'zip':('def main() -> int:\n    values = [1]\n    for a, b in zip(values, [2]):\n        values.append(a + b)\n    return 0\n',1),
 'comprehension':('def grow(values: mut list[int]) -> int:\n    values.append(2)\n    return 1\ndef main() -> int:\n    values = [1]\n    output = [grow(mut values) for value in values]\n    return len(output)\n',1),
 'success':(root/'tests/lang/iteration_identity.my',0),
}
callbacks=(root/'tests/lang/collection_read_callbacks.my').read_text()
callbacks=callbacks.replace('module collection_read_callbacks', 'module callbacks')
cases['callbacks']=(callbacks,0)
rows=[]
for backend in ['qbe','llvm']:
 for runtime in ['rc','gc']:
  for name,(source,status) in cases.items():
   path=source if isinstance(source,Path) else work/(name+'.my')
   if not isinstance(source,Path):path.write_text(source)
   binary=work/(runtime+'-'+backend+'-'+name)
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(path),'--backend',backend,'--mode','ReleaseFast','--cache-dir='+str(work/'cache-after'),'-o',str(binary)]
   if runtime=='rc':cmd+=['--rc-runtime=stats']
   if backend=='llvm':cmd+=['--llvm-opt','3','--lto']
   else:cmd+=['--qbe='+str(compiler.parent/'qbe')]
   build=subprocess.run(cmd,capture_output=True,text=True)
   if build.returncode: raise RuntimeError((name,cmd,build.stdout,build.stderr))
   run=subprocess.run([str(binary)],capture_output=True,text=True,env=dict(__import__('os').environ,MYLANG_OPTIONS='--gc-stress' if runtime=='gc' else ''),timeout=60)
   row=dict(backend=backend,runtime=runtime,name=name,exit=run.returncode,stdout=run.stdout,stderr=run.stderr,command=cmd,source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
   rows.append(row); (work/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
   print(backend,runtime,name,run.returncode,flush=True)
   assert run.returncode==status,(row,status)
   if status:assert 'R_LIST_ITERATION_MUTATION' in run.stderr,row
   if runtime=='rc':
    count=json.loads(next(line.split(' ',1)[1] for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')))
    assert count['heap_allocate']==count['retire'] and count['owner_acquire']+count['heap_allocate']==count['owner_release'] and count['hold_acquire']==count['hold_release'] and not count['saturated'],row
