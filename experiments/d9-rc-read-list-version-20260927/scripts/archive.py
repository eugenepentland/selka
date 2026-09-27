from pathlib import Path
import gzip,json,hashlib,subprocess,shutil,importlib.util
r=Path.cwd();w=r/'.tmp-mut-argument/read-version';a=r/'experiments/d9-rc-read-list-version-20260927';a.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def put(src,target=None,compress=False):
 src=Path(src);dst=a/(target or src.name);dst.parent.mkdir(parents=True,exist_ok=True);data=src.read_bytes();dst.write_bytes(gzip.compress(data,mtime=0) if compress else data)
for name in ('measure.py','validate.py','embed.py','accounted.py','guard.py','emitted.py','archive.py'):put(w/name,'scripts/'+name)
for name in ('embedding.c','embed.my','budget.my','guard.ssa','guard.s','guard.json','source-identity.json','residual-assembly.json','guest-emission.json','unaccounted-emission.json'):put(w/name)
for name in ('validation.json','embedding.json','accounted.json'):put(w/name,name+'.gz',True)
for name in ('embedding-invalid-budget.json','embedding-budget-no-allocation.json','embedding-inapplicable-stack-budget.json'):put(w/name,'development/'+name+'.gz',True)
for p in w.glob('*.log'):put(p,'logs/'+p.name+'.gz',True)
for p in r.glob('.tmp-mut-argument/read-version-*.log'):put(p,'logs/'+p.name+'.gz',True)
for p in w.glob('*.asm'):put(p,'assembly/'+p.name+'.gz',True)
put(w/'controls/results.json','controls.json.gz',True)
for p in (w/'controls').glob('*emitted.json.gz'):put(p,'emissions/accounted-'+p.name)
for p in w.glob('*emitted.json'):put(p,'emissions/'+p.name+'.gz',True)
for p in w.glob('*unaccounted.json.gz'):put(p,'emissions/'+p.name)
put(r/'tests/lang/rc_read_list_versions.my')
prior=r/'experiments/d9-rc-native-type-facts-20260927'
for name in ('accepted-gc-reference.json','accepted-gc-identities.json','accepted-gc-observations.json'):put(prior/name)
paths=['src/qbe_cow.zig','src/qbe_loop_version.zig','src/qbe_rc_read_version.zig','src/qbe_rc_read_version_test.zig','src/root_test.zig','tests/lang/rc_read_list_versions.my','SPEC.md']
patch=subprocess.run(['git','diff','HEAD','--',*paths],capture_output=True,check=True).stdout
for path in paths:
 if subprocess.run(['git','ls-files','--error-unmatch',path],capture_output=True).returncode:patch+=subprocess.run(['git','diff','--no-index','--','/dev/null',path],capture_output=True).stdout
(a/'source.patch.gz').write_bytes(gzip.compress(patch,mtime=0))
d=json.load(open(w/'controls/results.json'));inputs={}
for prog in d['identity']['programs']:
 for key in ('src','expected_path'):
  if key in prog:inputs[prog[key]]=sha(prog[key])
for e in d['samples'].values():
 for s in e['samples']:
  for k,v in s['run']['env'].items():
   if k.startswith('MYLANG_SCHEMATIC_INPUT_'):inputs[v]=sha(v)
# Current scalar fixture paths are frozen inputs too; source hashes live in
# validation/embedding rows. Actual SVG outputs are independently rechecked.
outputs={s['run']['svg']:sha(s['run']['svg']) for e in d['samples'].values() for s in e['samples'] if 'svg' in s['run']}
identity={'before_source':'e130e87ff3df525da7f1e39d0dee9890da8dff91','compilers':d['identity']['compilers'],'production_files':json.load(open(w/'source-identity.json'))['production'],'patch_sha256':hashlib.sha256(patch).hexdigest(),'cpu':3,'harness':{'path':str(w/'embedding'),'sha256':sha(w/'embedding'),'source_sha256':sha(w/'embedding.c')},'inputs':inputs,'outputs':outputs}
(a/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
print(a)
