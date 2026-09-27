from pathlib import Path
import collections,json,re,gzip,subprocess
r=Path.cwd();w=r/'.tmp-mut-argument/caller-field-audit';out={}
for backend in ('qbe','llvm'):
 result=json.loads((w/(backend+'-results.json')).read_text());names={x['symbol']:x['name'] for x in result['manifest']['functions']};hits=collections.Counter();sites=collections.Counter();edges=collections.Counter()
 for line in (w/(backend+'.branches.txt')).read_text().splitlines():
  found=re.findall(r'(myl_f_[a-f0-9]+)(\+0x[a-f0-9]+)? \([^)]*\)/(myl_rc_native_loan|myl_rc_native_retain|myl_qbe_rc_slot_drop)\+0x0',line)
  for name in {names.get(f,f) for f,offset,to in found if to=='myl_rc_native_loan'}:hits[name]+=1
  for f,offset,to in set(found):
   edges[(names.get(f,f),to)]+=1
   if to=='myl_rc_native_loan':sites[(names.get(f,f),offset)]+=1
 out[backend]={'interpretation':'qualitative exact guest call-site presence per sampled branch stack; not counts or percentages','samples':sum(x['hits'] for x in result['runs'][0]['symbols']),'throttle':result['runs'][0]['throttle'],'lost':result['runs'][0]['lost'],'callers':[{'name':k,'presence':v} for k,v in hits.most_common()],'sites':[{'name':k[0],'offset':k[1],'presence':v} for k,v in sites.most_common()], 'edges':[{'caller':k[0],'target':k[1],'presence':v} for k,v in edges.most_common()]}
 for name in ('vm::read_byte','vm::read_short','vm::run'):
  symbol=next(k for k,v in names.items() if v==name)
  p=subprocess.run(['objdump','-d','--disassemble='+symbol,result['binary']],capture_output=True,text=True,check=True)
  (w/(backend+'-'+name.replace('::','-')+'.asm')).write_text(p.stdout)
 print(backend,'samples',out[backend]['samples'],'top',out[backend]['callers'][:12])
(w/'branch-attribution.json').write_text(json.dumps(out,indent=2)+'\n')
# Static read-pair classification preserves source offsets; no dynamic weights.
emit=json.loads(gzip.decompress((r/'.tmp-mut-argument/field-list-read/final-emitted.json.gz').read_bytes()));vm=next(f for f in emit['functions'] if f['name']=='vm::run');rows=[];pc=None
for line in vm['il'].splitlines():
 m=re.match(r' dbgloc (\d+)',line)
 if m:pc=int(m[1])-1
 if 'call $myl_rc_native_loan(' in line:rows.append({'pc':pc,**vm['locations'][pc],'call':line.strip()})
source=(r/'.tmp-mut-argument/lox-post-record/current/guest/vm.my').read_text().splitlines();pairs=[]
for a,b in zip(rows,rows[1:]):
 if b['pc']==a['pc']+1 and b['line']==a['line']:
  pairs.append({'pc':[a['pc'],b['pc']],'line':a['line'],'source':source[a['line']-1].strip(),'type':'list[CallFrame], plain24-byte result' if 'a768868' in a['call'] else 'list[Value], plain16-byte result'})
assert len(rows)==48 and len(pairs)==13
(w/'vm-read-pairs.json').write_text(json.dumps(pairs,indent=2)+'\n')
for name in ('vm::read_byte','vm::read_short','vm::read_constant'):
 f=next(f for f in emit['functions'] if f['name']==name);(w/(name.replace('::','-')+'.il')).write_text(f['il'])
 print(name,'loans',f['il'].count('call $myl_rc_native_loan('),'lines',len(f['il'].splitlines()))
