"""Archive exact source-bound evidence; exclude compiled tools and caches."""
from pathlib import Path
import datetime, gzip, hashlib, io, json, os, shutil, subprocess, tarfile
ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-20261004')
RF=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-rf-20261004')
WORK=RF/'.mylang-cache/goal110-index-forward-rf'
DIAG=ROOT/'.mylang-cache/goal110-index-update'
G4=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf')
OUT=ROOT/'experiments/runtime-goal110-index-update-20261004'
SOURCE='14ffa2c0f385a11e5216bbdec5bdff429f9f981b'
BASE='6cf7bdce11bc205862bf75b9d9ce72e46caad0a2'
h=lambda data:hashlib.sha256(data).hexdigest()
index={'schema':'mylang-index-update-evidence-archive-v1','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_revision':SOURCE,'control_revision':BASE,'files':[],'packs':[],'excluded':'Compiled ELF tools/guests/objects, compiler caches and temporary directories. Live binaries remain pinned by receipts/manifests; no original artifact is changed.'}
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==SOURCE
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=RF,text=True).strip()==SOURCE

def save(path,name,compress=False):
 data=Path(path).read_bytes();dest=OUT/name;dest.parent.mkdir(parents=True,exist_ok=True)
 if compress:data_out=gzip.compress(data,mtime=0)
 else:data_out=data
 dest.write_bytes(data_out)
 index['files'].append({'path':name,'sha256':h(data_out),'bytes':len(data_out),'source_path':str(path),'source_sha256':h(data),'source_bytes':len(data),'encoding':'gzip' if compress else 'identity'})

def select(base):
 keep=[]
 for parent,dirs,files in os.walk(base):
  dirs[:]=sorted(d for d in dirs if d not in {'bin','tmp','mycache','build-cache','cache','.mylang-cache','__pycache__'} and 'zig-' not in d)
  for name in sorted(files):
   p=Path(parent)/name
   if p.suffix in {'.o','.a','.so','.pyc','.lock'}:continue
   with p.open('rb') as stream:magic=stream.read(4)
   if magic==b'\x7fELF':continue
   # Metadata, source snapshots and complete process streams only.
   if any(s in {'.json','.log','.exit','.py','.my','.ssa','.asm','.stderr','.stdout','.patch','.md','.zig','.txt'} for s in p.suffixes):keep.append(p)
 return keep

def pack(name,base,files):
 dest=OUT/name;entries=[]
 with dest.open('wb') as raw,gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as zipped,tarfile.open(fileobj=zipped,mode='w|') as tar:
  for path in sorted(files):
   data=path.read_bytes();rel=str(path.relative_to(base));info=tarfile.TarInfo(rel);info.size=len(data);info.mtime=0;info.mode=0o644;tar.addfile(info,io.BytesIO(data))
   entries.append({'path':rel,'sha256':h(data),'bytes':len(data),'source_path':str(path)})
 index['packs'].append({'path':name,'sha256':h(dest.read_bytes()),'bytes':dest.stat().st_size,'entries':entries})

reports=['screen-raw.json','screen.json','screen-comparison.json','paired-screen.json','paired-repeat.json','qualification.json','holdouts.json']
for name in reports:save(WORK/name,'reports/'+name+'.gz',True)
for path in sorted(WORK.iterdir()):
 if path.is_file() and path.name not in reports and path.suffix in {'.py','.json','.log','.exit'}:save(path,'official/'+path.name)
save(WORK/'runner/manifest.json','official/runner-manifest.json.gz',True)
for name in ['build-log.json','progress.json']:
 save(WORK/'runner'/name,'official/runner-'+name+'.gz',True)
pack('official-native.tar.gz',WORK/'native-checks',select(WORK/'native-checks'))
pack('official-static.tar.gz',WORK/'static',select(WORK/'static'))
pack('diagnostic-history.tar.gz',DIAG,select(DIAG))
for name in ['compiler-receipt.json','runner/manifest.json']:
 save(G4/name,'control/'+name.replace('/','-')+'.gz',True)
for side,base in [('candidate',WORK),('control',G4)]:
 m=json.loads((base/'runner/manifest.json').read_text())
 for name,path in m['identity']['binary_paths'].items():
  meta=Path(path+'.qbe-manifest.json')
  if meta.is_file():save(meta,'native-metadata/'+side+'/'+name.replace('/','-')+'.json.gz',True)
commands=json.loads((WORK/'timing-commands.json').read_text())
for path,digest in commands['helper_sha256'].items():
 path=Path(path);assert h(path.read_bytes())==digest
 rel=path.relative_to(RF)
 save(path,'helpers/'+str(rel).replace('.mylang-cache/goal110-index-forward-rf/','timing/'))
source_files=[ROOT/p for p in ['SPEC.md','src/qbe.zig','src/qbe_managed.zig','src/qbe_positive_index.zig','src/qbe_rc_index_update.zig','src/qbe_rc_index_update_test.zig','src/qbe_rc_nonheld_capture.zig','src/root_test.zig']]
pack('production-source.tar.gz',ROOT,source_files)
patch=subprocess.check_output(['git','diff',BASE,SOURCE,'--','SPEC.md','src'],cwd=ROOT)
(OUT/'production.patch').write_bytes(patch)
index['files'].append({'path':'production.patch','sha256':h(patch),'bytes':len(patch),'encoding':'identity','command':['git','diff',BASE,SOURCE,'--','SPEC.md','src']})
(OUT/'index.json').write_text(json.dumps(index,indent=2)+'\n')
print(json.dumps({'index_schema':index['schema'],'index_sha256':h((OUT/'index.json').read_bytes()),'files':len(index['files']),'packs':[{k:v for k,v in p.items() if k!='entries'}|{'entries':len(p['entries'])} for p in index['packs']]}),flush=True)
