#!/usr/bin/env python3
"""Static instruction paths, explicit branch assumptions; no execution/timing."""
from pathlib import Path
import collections, hashlib, json, re
lane=Path(__file__).resolve().parents[2]
work=lane/'.tmp-lox-vm-numeric-20261003'
prefix=[('jb',False,'ordinary admitted native frame'),('jl',False,'stack_top subtract does not overflow'),('jne',True,'right index positive and below length'),('je',False,'right tag is not nil'),('je',False,'right tag is not bool'),('je',True,'right tag is number'),('jl',False,'left index subtract does not overflow'),('jne',True,'left index positive and below length'),('je',False,'left tag is not nil'),('je',False,'left tag is not bool'),('je',True,'left tag is number')]
suffix=[('je',False,'stack list is non-null'),('jne',False,'ordinary mutable list flags'),('jb',True,'stack list has one owner'),('jge',True,'left write index nonnegative'),('jb',True,'left write index below length')]
ops=['greater','less','subtract','multiply','divide']
rows={}
for arm in ['baseline','v1']:
 path=work/(arm+'-numeric.qbe.asm')
 instructions=[]
 for line in path.read_text().splitlines():
  m=re.match(r'\s*([0-9a-f]+):\s+(\S+)\s*(.*)',line)
  if m: instructions.append((int(m[1],16),m[2],m[3],line))
 addresses={ins[0]:i for i,ins in enumerate(instructions)}
 armrows={}
 for opidx,op in enumerate(ops):
  dispatch=[('je',i==opidx,'opcode comparison '+ops[i]) for i in range(min(opidx+1,4))]
  decisions=prefix+dispatch+suffix
  used=[]; trace=[]; i=0
  while True:
   addr,mnemonic,args,line=instructions[i]; trace.append(line)
   if mnemonic=='ret': break
   if mnemonic=='jmp': i=addresses[int(args.split()[0],16)]; continue
   if mnemonic.startswith('j'):
    assert len(used)<len(decisions),(arm,op,hex(addr),'unexpected branch')
    expected,taken,reason=decisions[len(used)]
    assert mnemonic==expected,(arm,op,hex(addr),mnemonic,expected,reason)
    used.append({'address':hex(addr),'mnemonic':mnemonic,'taken':taken,'reason':reason})
    if taken: i=addresses[int(args.split()[0],16)]; continue
   assert mnemonic!='ud2',(arm,op,'trap reached')
   i+=1
  assert len(used)==len(decisions),(arm,op,'unused decisions',decisions[len(used):])
  outfile=work/(arm+'-'+op+'.path.asm'); outfile.write_text('\n'.join(trace)+'\n')
  counts=collections.Counter(re.match(r'\s*[0-9a-f]+:\s+(\S+)',line)[1] for line in trace)
  armrows[op]={'instructions':len(trace),'mnemonics':dict(counts),'call_instructions':[line for line in trace if re.search(r':\s+call\b',line)],'assumptions':used,'path_sha256':hashlib.sha256(outfile.read_bytes()).hexdigest()}
 rows[arm]=armrows
result={'kind':'static paths only; ordinary successful positive indices, unique mutable stack; callee bodies excluded','arms':rows,'delta':{op:rows['v1'][op]['instructions']-rows['baseline'][op]['instructions'] for op in ops}}
(work/'paths.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({arm:{op:r['instructions'] for op,r in values.items()} for arm,values in rows.items()}))
print('delta',result['delta'])
