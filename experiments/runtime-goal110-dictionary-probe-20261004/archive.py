"""Archive exact ordinary-found publication evidence without changing artifacts."""
from pathlib import Path
import datetime,gzip,hashlib,io,json,subprocess,tarfile
ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-dict-read-20261004')
WORK=ROOT/'.mylang-cache/goal110-dict-probe-debug'
NATIVE=ROOT/'.mylang-cache/goal110-dict-probe'
CONTROL=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-rf-20261004/.mylang-cache/goal110-index-forward-rf')
OUT=ROOT/'experiments/runtime-goal110-dictionary-probe-20261004'
SOURCE='64fb7e62732db9cea46414248fd59ba362e31b56'
BASE='eaf4cda8f5c758cadafaadfa5e328c0fba252ac6'
h=lambda data:hashlib.sha256(data).hexdigest()
index={'schema':'mylang-dictionary-probe-evidence-archive-v1','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_revision':SOURCE,'control_revision':'14ffa2c0f385a11e5216bbdec5bdff429f9f981b','base_revision':BASE,'files':[],'packs':[],'excluded':'Compiled tools/guests/native test binaries/objects and caches; live bytes remain bound by original immutable receipts/manifests. No original artifact is modified.'}
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==SOURCE

def save(path,name,compress=False):
 data=Path(path).read_bytes();dest=OUT/name;dest.parent.mkdir(parents=True,exist_ok=True);stored=gzip.compress(data,mtime=0) if compress else data;dest.write_bytes(stored)
 index['files'].append({'path':name,'sha256':h(stored),'bytes':len(stored),'source_path':str(path),'source_sha256':h(data),'source_bytes':len(data),'encoding':'gzip' if compress else 'identity'})

def pack(name,entries):
 dest=OUT/name;members=[]
 with dest.open('wb') as raw,gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as zipped,tarfile.open(fileobj=zipped,mode='w|') as tar:
  for rel,data,origin in sorted(entries):
   info=tarfile.TarInfo(rel);info.size=len(data);info.mtime=0;info.mode=0o644;tar.addfile(info,io.BytesIO(data));members.append({'path':rel,'sha256':h(data),'bytes':len(data),**origin})
 index['packs'].append({'path':name,'sha256':h(dest.read_bytes()),'bytes':dest.stat().st_size,'entries':members})

for p in sorted(WORK.iterdir()):
 if p.is_file() and p.suffix in {'.json','.py','.log','.exit','.md'}:
  compress=p.stat().st_size>100000;save(p,'official/'+p.name+('.gz' if compress else ''),compress)
for p in sorted((NATIVE/'logs').iterdir()):
 if p.is_file():save(p,'logs/'+p.name)
for p in sorted(NATIVE.iterdir()):
 if p.is_file():save(p,'native/'+p.name)
for p in sorted((NATIVE/'native-proof').glob('*.json')):save(p,'native/proof/'+p.name)
pack('optimized-static.tar.gz',[(str(p.relative_to(WORK/'static')),p.read_bytes(),{'source_path':str(p)}) for p in (WORK/'static').iterdir() if p.is_file()])
for name in ['compiler-receipt.json','runner/manifest.json']:save(CONTROL/name,'control/'+name.replace('/','-')+'.gz',True)
save(WORK/'runner/manifest.json','official/runner-manifest.json.gz',True)
for side,base in [('candidate',WORK),('control',CONTROL)]:
 m=json.loads((base/'runner/manifest.json').read_text())
 for name,path in m['identity']['binary_paths'].items():
  assert h(Path(path).read_bytes())==m['binary_hashes'][name]
  mp=Path(path+'.qbe-manifest.json')
  if mp.is_file():save(mp,'native-metadata/'+side+'/'+name.replace('/','-')+'.json.gz',True)
for path,digest in json.loads((WORK/'repeat-commands.json').read_text())['helper_sha256'].items():
 p=Path(path);assert h(p.read_bytes())==digest;rel=str(p.relative_to(ROOT));save(p,'helpers/'+rel.replace('.mylang-cache/goal110-dict-probe-debug/','timing/'))
changed=['SPEC.md','src/native_dictionary.c','src/native_dictionary.h','scripts/test_native_memory.py','tests/native_dictionary_probe_test.c']
pack('production-source.tar.gz',[(p,(ROOT/p).read_bytes(),{'source_path':str(ROOT/p)}) for p in changed])
receipt=json.loads((NATIVE/'native-proof/receipt.json').read_text());tested=[]
for rel,digest in receipt['sources'].items():
 if rel=='SPEC.md':continue  # Documentation is not compiled; its tested hash remains in the receipt.
 data=(ROOT/rel).read_bytes();how='Exact final source'
 if h(data)!=digest:
  assert rel in ['src/native_dictionary.c','tests/native_dictionary_probe_test.c'];data=data.replace(b'PY-DICT-4',b'DICT-PROBE-FOUND-1');how='Reverse only the documented C-comment requirement tag substitution'
 assert h(data)==digest;tested.append((rel,data,{'source_path':str(ROOT/rel),'reconstruction':how}))
pack('native-tested-source.tar.gz',tested)
patch=subprocess.check_output(['git','diff',BASE,SOURCE,'--',*changed],cwd=ROOT);(OUT/'production.patch').write_bytes(patch);index['files'].append({'path':'production.patch','sha256':h(patch),'bytes':len(patch),'encoding':'identity','command':['git','diff',BASE,SOURCE,'--',*changed]})
(OUT/'index.json').write_text(json.dumps(index,indent=2)+'\n');print(json.dumps({'schema':index['schema'],'sha256':h((OUT/'index.json').read_bytes()),'files':len(index['files']),'packs':[{k:v for k,v in p.items() if k!='entries'}|{'entries':len(p['entries'])} for p in index['packs']]}),flush=True)
