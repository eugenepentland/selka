import bisect,collections,json,re,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/tree-profile';result={}
make='myl_f_d05aa2a15fb3c40efeeb03bec445393f00074484cf01c8fb2da90ca6695a5531'
for backend in ('qbe','llvm'):
 for arm in ('rc','gc'):
  prefix=backend+'-'+arm; samples=(work/(prefix+'.samples.txt')).read_text();syms=collections.Counter();pcs=collections.Counter();n=0
  for line in samples.splitlines():
   m=re.match(r'\s*(\d+)\s+([0-9a-f]+)\s+(.+?)\s+\(',line)
   if not m:continue
   period=int(m[1]);syms[m[3]]+=period;n+=1
   if m[3]==make:pcs[int(m[2],16)]+=period
  row={'samples':n,'total_period':sum(syms.values()),'symbols':[{'symbol':s,'period':p,'share':p/sum(syms.values())} for s,p in syms.most_common(20)]}
  if arm=='rc':
   binary=work/(backend+'-rc-repeat');dis=subprocess.check_output(['objdump','-d','--disassemble='+make,str(binary)],text=True)
   (work/(backend+'-make.asm')).write_text(dis);instructions={}
   for line in dis.splitlines():
    m=re.match(r'\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(.*)',line)
    if m:instructions[int(m[1],16)]=m[3]
   addresses=sorted(instructions)
   row['make_hot_instructions']=[{'address':hex(ip),'instruction':instructions.get(ip,instructions.get(addresses[bisect.bisect_right(addresses,ip)-1],'')),'period':p,'global_share':p/sum(syms.values())} for ip,p in pcs.most_common(30)]
  result[prefix]=row
(work/'analysis.json').write_text(json.dumps(result,indent=2)+'\n')
for name,r in result.items():print(name,[(x['symbol'],round(x['share']*100,2)) for x in r['symbols'][:8]])
