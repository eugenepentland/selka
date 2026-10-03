#!/usr/bin/env python3
"""Static selected-operation tails to VM loop, no execution/timing."""
from pathlib import Path
import collections,hashlib,json,re
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-vm-numeric-20261003'
starts={'baseline':{'greater':0x1131ec9,'less':0x11332ff,'subtract':0x11332ef,'multiply':0x113331a,'divide':0x113332a},'v1':{'greater':0x11325c9,'less':0x1133a4d,'subtract':0x1133a3a,'multiply':0x1133ac0,'divide':0x1133ad0}}
ends={'baseline':0x112f2f0,'v1':0x112f9f0};rows={}
for arm in starts:
 ins=[]
 for line in (work/(arm+'-run.llvm.asm')).read_text().splitlines():
  m=re.match(r'\s*([0-9a-f]+):\s+(\S+)\s*(.*)',line)
  if m:ins.append((int(m[1],16),m[2],m[3],line))
 addrs={v[0]:i for i,v in enumerate(ins)};rows[arm]={}
 for op,start in starts[arm].items():
  choices=[('je',False,'stack non-null'),('jne',False,'ordinary mutable flags'),('jb',True,'one owner'),('jns',True,'positive left write index'),('jb',True,'index below length')] if arm=='v1' and op=='greater' else [('je',False,'stack non-null'),('jne',False,'ordinary mutable flags'),('jb',True,'one owner'),('jns',True,'positive left write index'),('jae',False,'index below length')]
  i=addrs[start];trace=[];used=[]
  while ins[i][0]!=ends[arm]:
   addr,m,args,line=ins[i];trace.append(line)
   if m=='jmp':i=addrs[int(args.split()[0],16)];continue
   if m.startswith('j'):
    assert len(used)<len(choices),(arm,op,hex(addr),'unexpected branch')
    expected,taken,reason=choices[len(used)];assert m==expected,(arm,op,hex(addr),m,expected)
    used.append({'address':hex(addr),'mnemonic':m,'taken':taken,'reason':reason})
    if taken:i=addrs[int(args.split()[0],16)];continue
   assert m not in ['ret','ud2','call'],(arm,op,'unexpected terminator/call')
   i+=1
  assert len(used)==len(choices)
  out=work/(arm+'-'+op+'.llvm-tail.asm');out.write_text('\n'.join(trace)+'\n')
  rows[arm][op]={'instructions':len(trace),'mnemonics':dict(collections.Counter(re.match(r'\s*[0-9a-f]+:\s+(\S+)',l)[1] for l in trace)),'assumptions':used,'path_sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
res={'kind':'actual LLVM O3/full LTO inlined numeric selected-operation tails to shared VM loop; not full opcode dispatch, no perf','arms':rows,'delta':{op:rows['v1'][op]['instructions']-rows['baseline'][op]['instructions'] for op in starts['v1']}}
(work/'llvm-paths.json').write_text(json.dumps(res,indent=2)+'\n')
print({a:{o:r['instructions'] for o,r in rs.items()} for a,rs in rows.items()});print(res['delta'])
