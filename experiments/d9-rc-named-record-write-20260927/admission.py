from pathlib import Path
import json,re
w=Path('.tmp-named-record')
before=json.loads((w/'lox-before-builds.json').read_text());after=json.loads((w/'lox-after-builds.json').read_text())
def symbols(build,cache):
 names={f['symbol']:f['name'] for f in build['builds'][0]['manifest']['functions']};found={}
 for p in cache.glob('frontend/fragments/*/il/*'):
  text=p.read_text();m=re.match(r'dbgfile "([^"]+)"',text)
  if m and m[1] in names:found[names[m[1]]]=text
 return found
b=symbols(before,w/'lox-before-cache');a=symbols(after,w/'lox-after-cache');marker='# RC-PLAIN-RECORD-WRITE-1'
changes=[{'name':name,'before':b[name].count(marker),'after':text.count(marker)} for name,text in a.items() if text.count(marker)!=b[name].count(marker)]
def loans(text):
 d={}
 for typ in re.findall(r'call \$myl_rc_native_loan\(l %heap, l extern \$(\w+)',text):d[typ]=d.get(typ,0)+1
 return d
r={'before_compiler_sha256':before['compiler_sha256'],'after_compiler_sha256':after['compiler_sha256'],'changes':changes,'vm_before':loans(b['vm::run']),'vm_after':loans(a['vm::run']),'vm_tail_before':b['vm::run'].count(marker),'vm_tail_after':a['vm::run'].count(marker)}
assert r['vm_tail_before']==18 and r['vm_tail_after']==22
assert sum(r['vm_before'].values())==58 and sum(r['vm_after'].values())==50
for key,value in r['vm_after'].items():assert r['vm_before'][key]==value
assert set(x['name'] for x in changes)=={'vm::run','compiler::init_compiler'}
for arm,texts in [('before',b),('after',a)]:
 for name in ('vm::run','compiler::init_compiler'):(w/f'{name.replace("::","-")}-{arm}.il').write_text(texts[name])
(w/'admission-final.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r,indent=2))
