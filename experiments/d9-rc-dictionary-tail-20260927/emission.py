from pathlib import Path
import json,subprocess,hashlib
r=Path.cwd();w=r/'.tmp-rc/dict-tail';cs={'before':r/'.tmp-rc/install-dict-tail-before/bin/mylang','after':r/'.tmp-rc/install-dict-tail-final/bin/mylang'}
d=[]
for side,c in cs.items():
 cmd=[str(c),'emit-qbe',str(r/'bench/parity/micro/dict_count.my'),'--rc-runtime'];p=subprocess.run(cmd,text=True,capture_output=True);assert p.returncode==0,p.stderr;(w/f'{side}-emitted.json').write_text(p.stdout)
 f=next(x for x in json.loads(p.stdout)['functions'] if x['name']=='main');il=f['il'];(w/f'{side}-main.ssa').write_text(il)
 d.append(dict(side=side,command=cmd,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),symbol=f.get('symbol'),bytes=len(il),marker=il.count('# RC-DICTIONARY-TAIL-1'),unique=il.count('call $myl_qbe_rc_unique_local'),begin=il.count('call $myl_qbe_rc_scope_begin'),pin=il.count('call $myl_qbe_rc_scope_pin'),end=il.count('call $myl_qbe_rc_scope_end'),write=il.count('call $myl_native_dictionary_write'),frame=il.count('call $myl_qbe_rc_frame_enter'),loan=il.count('call $myl_rc_native_loan'),il_sha256=hashlib.sha256(il.encode()).hexdigest()))
(w/'emission.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d,indent=2))
a,b=d;assert b['marker']==1 and a['marker']==0
for k in ('unique','begin','pin','end'):assert b[k]==a[k]-1,(k,a,b)
for k in ('write','frame','loan'):assert b[k]==a[k],(k,a,b)
