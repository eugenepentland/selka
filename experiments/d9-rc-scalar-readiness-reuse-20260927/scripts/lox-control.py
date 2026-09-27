from pathlib import Path
import os,subprocess,json,hashlib,gzip
root=Path.cwd();w=root/'.tmp-mut-argument/scalar-readiness-prototype';guest=root/'.tmp-mut-argument/type-facts/measure/guest'
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(w)
compilers={'before':root.parent/'d9-rc-readiness-before-astra/.tmp-readiness/install/bin/mylang','after':w/'install/bin/mylang'}
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
d={'sources':{str(p.relative_to(guest)):sha(p) for p in guest.rglob('*.my')},'rows':[]};path=w/'lox-emission.json'
for side,c in compilers.items():
 cmd=[root/'scripts/build-slot.sh','build',c,'emit-project-qbe','main.my','--no-cache','--rc-runtime'];p=subprocess.run(list(map(str,cmd)),cwd=guest,env=e,capture_output=True,timeout=600)
 row={'side':side,'command':list(map(str,cmd)),'cwd':str(guest),'compiler_sha256':sha(c),'status':p.returncode,'stderr':p.stderr.decode()};d['rows'].append(row);path.write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row
 out=w/('lox-'+side+'-emitted.json.gz');out.write_bytes(gzip.compress(p.stdout,mtime=0));row.update(emission=str(out),sha256=hashlib.sha256(p.stdout).hexdigest());manifest=json.loads(p.stdout);row['functions']=[{'name':f['name'],'symbol':f['symbol'],'il_sha256':hashlib.sha256(f['il'].encode()).hexdigest(),'flags':f['il'].count('%rcappend0 =l')} for f in manifest['functions']];path.write_text(json.dumps(d,indent=2)+'\n');print(side,len(row['functions']),sum(x['flags'] for x in row['functions']),flush=True)
a={f['symbol']:f for f in d['rows'][0]['functions']};b={f['symbol']:f for f in d['rows'][1]['functions']}
d['changed']=[a[k]['name'] for k in a if a[k]!=b[k]]
assert d['changed']==['object::new_closure']
path.write_text(json.dumps(d,indent=2)+'\n')
print('One changed Lox function: object::new_closure',flush=True)
