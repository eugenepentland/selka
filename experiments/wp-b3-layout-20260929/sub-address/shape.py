import collections,json,pathlib,re
out=pathlib.Path('.tmp/sub-address/production');summary={}
for name in ['vm-load_frame','vm-run']:
 modes={}
 for mode in ['control','candidate']:
  ops=collections.Counter();rows=[]
  for line in (out/(name+'-'+mode+'.s')).read_text().splitlines():
   line=line.strip()
   if not line or line[0] in '.#/' or line.endswith(':'):continue
   if not re.match(r'^[a-z][a-z0-9]*\s',line) and line not in ['ret','endbr64','ud2']:continue
   ops[line.split()[0]]+=1;rows.append(line)
  modes[mode]={'static_instructions':len(rows),'ops':dict(ops),'negative_prefix_displacement_accesses':sum(bool(re.search(r'-(16|24|32)\(',v)) for v in rows)}
 summary[name]=modes
(out/'shape.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
