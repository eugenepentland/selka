import os,subprocess,sys
from pathlib import Path
here=Path(__file__).resolve().parent
root=Path.cwd();base=root/'.tmp/memory-closeout/A02/field-augmented-validation'
compilers={'baseline':Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang'),'candidate':root/'.zig-cache/o/4adaf9b792cc2ec351338d318aaf1334/mylang'}
for label,compiler in compilers.items():
 for case in ['root-rebinding','field-replacement','sibling-write','borrowed-return','fixture']:
  if label=='baseline' and case=='root-rebinding':continue
  output=base/(label+'-'+case)
  options=['--ordinary-only','--expected-output',str(here/'fixture.stdout')] if case=='fixture' else ['--controls']
  result=subprocess.run([sys.executable,'-B',str(here/'matrix.py'),'--compiler',str(compiler),'--output',str(output),'--case',case,*options])
  if result.returncode:raise SystemExit(result.returncode)
