from pathlib import Path
import json,subprocess,hashlib,struct,os
r=Path.cwd();w=r/'.tmp-rc/owned-hoist';c=r/'.tmp-rc/install-owned-hoist-final/bin/mylang';m=json.loads((w/'full/results.json').read_text());env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def section(p):
 b=p.read_bytes();assert b[:6]==b'\x7fELF\x02\x01';h=struct.unpack_from('<16sHHIQQQIHHHHHH',b);off,size,count,names=h[6],h[11],h[12],h[13];s=[struct.unpack_from('<IIQQQQIIQQ',b,off+i*size) for i in range(count)];ns=s[names];strings=b[ns[4]:ns[4]+ns[5]]
 for a in s:
  if strings[a[0]:].split(b'\0',1)[0]==b'.text':return hashlib.sha256(b[a[4]:a[4]+a[5]]).hexdigest()
 raise AssertionError(p)
d={'measured_compiler':m['compilers']['after'],'final_compiler':{'path':str(c),'sha256':digest(c)},'emissions':[],'builds':[]}
def save():(w/'final-equivalence.json').write_text(json.dumps(d,indent=2)+'\n')
for name,s in m['sources'].items():
 p=subprocess.run([str(c),'emit-qbe',s['path'],'--rc-runtime'],env=env,text=True,capture_output=True);assert p.returncode==0,p.stderr
 before=json.loads((w/f'{name}-after-emitted.json').read_text());after=json.loads(p.stdout)
 assert before['functions']==after['functions'],name
 d['emissions'].append({'case':name,'functions_equal':True});save()
for row in m['builds']:
 if row['side']!='after':continue
 cmd=list(row['command']);cmd[2]=str(c);at=cmd.index('-o')+1;before=Path(cmd[at]);after=before.with_name('final-'+before.name);cmd[at]=str(after)
 p=subprocess.run(cmd,env=env,text=True,capture_output=True);out={'case':row['case'],'backend':row['backend'],'stats':row['stats'],'command':cmd,'status':p.returncode,'stderr':p.stderr};d['builds'].append(out);save();assert p.returncode==0,out
 out.update(before_binary_sha256=digest(before),final_binary_sha256=digest(after),before_text_sha256=section(before),final_text_sha256=section(after));save();assert out['before_text_sha256']==out['final_text_sha256'],out
 print(row['case'],row['backend'],row['stats'],'identical .text',flush=True)
