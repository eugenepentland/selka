import subprocess,sys
from pathlib import Path
here=Path(__file__).resolve().parent;root=Path.cwd();base=root/'.tmp/memory-closeout/A02/field-augmented-validation'
compilers={'baseline':Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang'),'candidate':root/'.zig-cache/o/75e409ad69f15be3d392595458eae627/mylang'}
for label,compiler in compilers.items():
 for case in ['fixture-ordinary','root-rebinding','field-replacement','sibling-write','borrowed-return']:
  if label=='baseline' and case!='fixture-ordinary':continue
  options=['--ordinary-only','--expected-output',str(here/'fixture.stdout')] if case=='fixture-ordinary' else ['--controls']
  result=subprocess.run([sys.executable,'-B',str(here/'matrix.py'),'--compiler',str(compiler),'--output',str(base/(label+'-'+case+'-followup')),'--case',case,*options])
