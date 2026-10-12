#!/usr/bin/env python3
"""Apply checker-directed snapshots to owned leaf files; never dependencies."""
import json,pathlib,re,sys
base=pathlib.Path(__file__).resolve().parent;root=base.parent/'eda/source/src';seen=set();changes=[]
for row in json.loads(pathlib.Path(sys.argv[1]).read_text())['modules']:
 m=re.match(r'([^:]+):(\d+):(\d+): error\[(E_SINGLE_OWNER_BORROW|E_SINGLE_OWNER_OVERLAP)\]',row['stderr'])
 if not m or not m[1].startswith(('export_kicad','kicad_')):continue
 if m[1] in ('export_kicad_sch.my','export_kicad_sch_test.my'):continue
 key=(m[1],int(m[2]));
 if key in seen:continue
 seen.add(key);p=root/m[1];lines=p.read_text().splitlines();idx=int(m[2])-1;line=lines[idx];start=int(m[3])-1
 if ' = ' in line and start<line.index(' = '):start=line.index(' = ')+3
 end=start;depth=0;quote=None
 while end<len(line):
  c=line[end]
  if quote:
   if c==quote and (end==0 or line[end-1]!='\\'):quote=None
  elif c in "\"'":quote=c
  elif c in '([':depth+=1
  elif c in ')]}':
   if depth==0:break
   depth-=1
  elif depth==0 and (c==',' or c.isspace()):break
  end+=1
 expr=line[start:end]
 if re.search(r'\.(append|add|extend|push|clear|sort|reverse|insert)\(',expr):continue
 if not expr or expr.endswith('.copy()') or expr in {'mut','if','then','else','for','return','case','try','const','public','func'}:continue
 lines[idx]=line[:end]+'.copy()'+line[end:];p.write_text('\n'.join(lines)+'\n');changes.append({'file':m[1],'line':idx+1,'selection':expr})
print(json.dumps(changes,indent=2))
