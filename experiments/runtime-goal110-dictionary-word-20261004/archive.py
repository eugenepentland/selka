"""Preserve typed dictionary read evidence without executing or modifying guests."""
from pathlib import Path
import datetime,gzip,hashlib,io,json,subprocess,tarfile

ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-dict-word-integrated-20261004')
WORK=ROOT/'.mylang-cache/goal110-dict-word-debug'
PROOF=ROOT/'.mylang-cache/goal110-dict-word'
CONTROL=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-integrated-20261004/.mylang-cache/goal110-integrated-debug')
OUT=ROOT/'experiments/runtime-goal110-dictionary-word-20261004'
SOURCE='a2dfdfa994e19ac3c80373a443913c7ecdef23d7'
BASE='1a3980631e79bc65f048acd063d7250800f01901'
h=lambda b:hashlib.sha256(b).hexdigest()
index={'schema':'mylang-dictionary-word-evidence-archive-v1','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_revision':SOURCE,'control_revision':BASE,'files':[],'packs':[],'live_bindings':[],'excluded':'Compiled hosts, guests, native test binaries, objects and caches; original immutable receipts/manifests bind the live artifacts. One changed-source pack is retained; unchanged sources remain reconstructible from the pinned Git revisions. No artifact is modified.'}
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==SOURCE
def save(path,name):
 data=Path(path).read_bytes();compress=len(data)>100000;dest=OUT/(name+('.gz' if compress else ''));dest.parent.mkdir(parents=True,exist_ok=True);stored=gzip.compress(data,mtime=0) if compress else data;dest.write_bytes(stored)
 index['files'].append({'path':str(dest.relative_to(OUT)),'sha256':h(stored),'bytes':len(stored),'source_path':str(path),'source_sha256':h(data),'source_bytes':len(data),'encoding':'gzip' if compress else 'identity'})
def pack(name,entries):
 dest=OUT/name;members=[]
 with dest.open('wb') as raw,gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as zipped,tarfile.open(fileobj=zipped,mode='w|') as tar:
  for rel,data,origin in sorted(entries):
   info=tarfile.TarInfo(rel);info.size=len(data);info.mtime=0;info.mode=0o644;tar.addfile(info,io.BytesIO(data));members.append({'path':rel,'sha256':h(data),'bytes':len(data),**origin})
 index['packs'].append({'path':name,'sha256':h(dest.read_bytes()),'bytes':dest.stat().st_size,'entries':members})
def bind(path,expected=None,kind='artifact'):
 p=Path(path).resolve(strict=True);digest=h(p.read_bytes())
 if expected:assert digest==expected,str(p)
 index['live_bindings'].append({'path':str(p),'sha256':digest,'kind':kind})

for directory,prefix in [(WORK,'official'),(WORK/'timing-02','official/timing-02'),(WORK/'repeat','official/repeat'),(PROOF,'proof'),(PROOF/'logs','logs'),(PROOF/'native-proof','proof/native-proof-01'),(PROOF/'native-proof-02','proof/native-proof-02')]:
 for p in sorted(directory.iterdir()):
  if p.is_file() and p.suffix in {'.json','.py','.log','.exit','.md','.patch'}:save(p,prefix+'/'+p.name)
language=PROOF/'language';save(language/'dictionary-word.my','language/dictionary-word.my');save(language/'native-checks.py','language/native-checks.py')
save(language/'official-proof-01/report.json','language/official-report.json')
pack('language-emission-and-sidecars.tar.gz',[(str(p.relative_to(language/'official-proof-01')),p.read_bytes(),{'source_path':str(p)}) for p in (language/'official-proof-01').glob('*/*/*.json') if p.name in ['emission.json','guest.qbe-manifest.json']])
pack('optimized-static.tar.gz',[(str(p.relative_to(PROOF/'static')),p.read_bytes(),{'source_path':str(p)}) for p in (PROOF/'static').rglob('*') if p.is_file()])
changed=subprocess.check_output(['git','diff','--name-only',BASE,SOURCE],cwd=ROOT,text=True).splitlines();assert len(changed)==8
pack('production-source.tar.gz',[(p,(ROOT/p).read_bytes(),{'source_path':str(ROOT/p)}) for p in changed])
patch=subprocess.check_output(['git','diff',BASE,SOURCE,'--',*changed],cwd=ROOT);p=OUT/'production.patch';p.write_bytes(patch);index['files'].append({'path':p.name,'sha256':h(patch),'bytes':len(patch),'encoding':'identity','command':['git','diff',BASE,SOURCE,'--',*changed]})
for prefix,base in [('candidate',WORK),('control',CONTROL)]:
 save(base/'compiler-receipt.json',prefix+'/compiler-receipt.json');save(base/'runner/manifest.json',prefix+'/runner-manifest.json')
 manifest=json.loads((base/'runner/manifest.json').read_text())
 for name,path in manifest['identity']['binary_paths'].items():
  bind(path,manifest['binary_hashes'][name],prefix+' guest')
  side=Path(path+'.qbe-manifest.json')
  if side.is_file():save(side,'native-metadata/'+prefix+'/'+name.replace('/','-')+'.json')
 receipt=json.loads((base/'compiler-receipt.json').read_text());bind(receipt['compiler_path'],receipt['compiler_sha256'],prefix+' compiler')
helpers=json.loads((WORK/'repeat/commands.json').read_text())['helper_sha256']
helpers.update(json.loads((PROOF/'preparation-commands.json').read_text())['helpers'])
for path,digest in helpers.items():
 p=Path(path);bind(p,digest,'helper');rel=str(p.relative_to(ROOT));save(p,'helpers/'+rel.replace('.mylang-cache/goal110-dict-word-debug/','timing/').replace('.mylang-cache/goal110-dict-word/','proof/'))
native=json.loads((PROOF/'native-proof-02/receipt.json').read_text())
for rel,digest in native['sources'].items():bind(ROOT/rel,digest,'native tested source')
unit=json.loads((PROOF/'focused-source-proof.json').read_text());data=(ROOT/'src/qbe_test.zig').read_bytes();old=data.replace(b'// spec-case: PY-DICT-4\n// spec-case: QBE-PURE-READ-1\ntest "PY-DICT-4 word',b'// spec: PY-DICT-4\n// spec-case: QBE-PURE-READ-1\ntest "PY-DICT-4 word').replace(b'// spec-case: RC-SITES-1\ntest "PY-DICT-4 word counting',b'// spec: RC-SITES-1\ntest "PY-DICT-4 word counting');assert h(old)==unit['comment_only_reconstruction']['tested_sha256']
pack('unit-tested-comment-snapshot.tar.gz',[('src/qbe_test.zig',old,{'source_path':str(ROOT/'src/qbe_test.zig'),'reconstruction':'Reverse exactly the two documented primary spec→spec-case comment corrections'})])
summary={}
for name in ['paired-screen','paired-repeat']:
 d=json.loads((WORK/(name+'.json')).read_text());summary[name]={'measurement_session_id':d['measurement_session_id'],'started_utc':d['started_utc'],'guest_finished_utc':d['guest_finished_utc'],'finished_utc':d['finished_utc'],'rounds':d['rounds'],'warmups':d['warmups'],'rows':[{k:r[k] for k in ['plan','medians_ns_per_iteration','comparisons']} for r in d['rows']]}
p=OUT/'timing-summary.json';p.write_text(json.dumps(summary,indent=2)+'\n');index['files'].append({'path':p.name,'sha256':h(p.read_bytes()),'bytes':p.stat().st_size,'encoding':'identity'})
for name in ['README.md','archive.py','verify-archive.py']:save(OUT/name,name)
(OUT/'index.json').write_text(json.dumps(index,indent=2)+'\n');print(json.dumps({'schema':index['schema'],'index_sha256':h((OUT/'index.json').read_bytes()),'files':len(index['files']),'packs':[{k:v for k,v in p.items() if k!='entries'}|{'entries':len(p['entries'])} for p in index['packs']],'live_bindings':len(index['live_bindings'])},indent=2))
