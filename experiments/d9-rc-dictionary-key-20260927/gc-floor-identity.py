from pathlib import Path
import hashlib,json,subprocess,struct,os
r=Path.cwd();w=r/'.tmp-rc/dict-key';d=json.loads((w/'controls-initial-partial.json').read_text());row=next(x for x in d['builds'] if x['mode']=='gc' and x['case']=='floor');cmd=list(row['command']);cmd[2]=str(r/'.tmp-rc/install-dict-key-before/bin/mylang');before=w/'control-before-gc-qbe-floor';cmd[cmd.index('-o')+1]=str(before);cmd=[x.replace('control-cache-prototype','control-cache-before') for x in cmd];env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_')};env['TMPDIR']=str(r/'.tmp-rc/tmp')
p=subprocess.run(cmd,env=env,text=True,capture_output=True);out={'before_build_command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'after_build':row};(w/'gc-floor-identity.json').write_text(json.dumps(out,indent=2)+'\n');assert p.returncode==0,p.stderr
before_manifest=json.loads(Path(str(before)+'.qbe-manifest.json').read_text());out['before_manifest']=before_manifest
# Read-only ELF section bytes, independent of timestamps/build IDs/debug paths.
def section(path,name):
 b=path.read_bytes();assert b[:6]==b'\x7fELF\x02\x01';off=struct.unpack_from('<Q',b,40)[0];size,count,strings=struct.unpack_from('<HHH',b,58);rows=[struct.unpack_from('<IIQQQQIIQQ',b,off+i*size) for i in range(count)];s=rows[strings];names=b[s[4]:s[4]+s[5]]
 for x in rows:
  at=x[0];n=names[at:names.index(0,at)].decode()
  if n==name:return b[x[4]:x[4]+x[5]]
 raise AssertionError(name)
paths={'before':before,'after':w/'control-prototype-gc-qbe-floor'}
out['binaries']={side:{'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'text_sha256':hashlib.sha256(section(path,'.text')).hexdigest()} for side,path in paths.items()}
out['identical_text']=section(paths['before'],'.text')==section(paths['after'],'.text')
(w/'gc-floor-identity.json').write_text(json.dumps(out,indent=2)+'\n');print(out['binaries'],out['identical_text']);assert out['identical_text']
