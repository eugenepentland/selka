"""Read-only native shapes at immutable Lox vm::run loan sites; no dynamic claim."""
from pathlib import Path
import collections,hashlib,json,re,struct,subprocess
root=Path.cwd();base=root.parent/'d9-rc-lox-probe-astra/.tmp-field'
manifest=base/'lox-final-qbe-0.qbe-manifest.json';binary=base/'lox-final-qbe-0'
identity=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
m=json.loads(manifest.read_text());symbol=next(f['symbol'] for f in m['functions'] if f['name']=='vm::run')
hits=[]
for p in (base/'lox-cache-final/frontend/fragments').glob('*/il/*'):
 text=p.read_text()
 if re.search(r'export function[^\n]*\$'+symbol+r'\(',text):hits.append((p,text))
assert hits and len({hashlib.sha256(s.encode()).hexdigest() for _,s in hits})==1
calls=collections.Counter(re.findall(r'call \$myl_rc_native_loan\(l %heap, l extern \$(\w+)',hits[0][1]))
data=binary.read_bytes();assert data[:6]==b'\x7fELF\x02\x01'
phoff=struct.unpack_from('<Q',data,32)[0];width,count=struct.unpack_from('<HH',data,54);segments=[]
for i in range(count):
 kind,flags,offset,address,_,filesz,memsz,align=struct.unpack_from('<IIQQQQQQ',data,phoff+i*width)
 if kind==1:segments.append((address,filesz,offset))
def read(address,size):
 for start,length,offset in segments:
  if start<=address and address+size<=start+length:return data[offset+address-start:offset+address-start+size]
 raise ValueError(address)
symbols={}
for line in subprocess.run(['nm','-S',str(binary)],capture_output=True,text=True,check=True).stdout.splitlines():
 fields=line.split()
 if len(fields)==4:symbols[fields[3]]=int(fields[0],16)
kinds=['plain','pointer','record','array','variant','owned_buffer','owned_pool','float','resource']
def native(address,depth=0):
 size,align,fields,n,count,stride,kind,collection,element,key=struct.unpack('<6Q2I2Q',read(address,72))
 result={'size':size,'kind':kinds[kind],'collection_kind':collection}
 if kind in (2,3,4) and depth<8:
  result['fields']=[{'offset':struct.unpack_from('<Q',read(fields+i*24,24))[0],'type':native(struct.unpack_from('<Q',read(fields+i*24,24),8)[0],depth+1)} for i in range(n)]
 return result
result={'static_only':True,'manifest':str(manifest),'manifest_sha256':identity(manifest),'binary_sha256':identity(binary),'symbol':symbol,'il':[{'path':str(p),'sha256':identity(p)} for p,_ in hits],'loan_calls_by_type':calls,'types':{name:native(symbols[name]) for name in calls}}
(root/'.tmp-mut-argument/loan-lox-static.json').write_text(json.dumps(result,indent=2)+'\n')
