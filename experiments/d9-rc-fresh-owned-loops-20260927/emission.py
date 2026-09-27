from pathlib import Path
import json,subprocess,hashlib,gzip
r=Path.cwd();w=r/'.tmp-rc/owned-hoist';cs={'before':r.parent/'d9-rc-integration/.tmp-rc/install-field-frame-span/bin/mylang','after':r/'.tmp-rc/install-owned-hoist/bin/mylang'}
ss={'fannkuch':r/'bench/parity/suite/fannkuch_redux.my','sieve':r/'bench/parity/suite/sieve.my','append':r/'bench/parity/micro/list_append_sum.my'}
data=[]
for name,source in ss.items():
 for side,c in cs.items():
  cmd=[str(c),'emit-qbe',str(source),'--rc-runtime'];p=subprocess.run(cmd,text=True,capture_output=True);assert p.returncode==0,p.stderr
  (w/f'{name}-{side}-emitted.json').write_text(p.stdout)
  for f in json.loads(p.stdout)['functions']:
   il=f['il'];data.append(dict(case=name,side=side,function=f['name'],symbol=f['symbol'] if 'symbol' in f else None,bytes=len(il),preheaders=il.count('@ce'),unique=il.count('call $myl_qbe_rc_unique_local'),frame=il.count('call $myl_qbe_rc_frame_enter'),il_sha256=hashlib.sha256(il.encode()).hexdigest()))
(w/'emission.json').write_text(json.dumps(data,indent=2)+'\n')
print(json.dumps(data,indent=2))
