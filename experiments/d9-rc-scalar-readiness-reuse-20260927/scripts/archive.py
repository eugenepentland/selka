from pathlib import Path
import gzip,json,hashlib,subprocess,shutil
r=Path.cwd();w=r/'.tmp-mut-argument/scalar-readiness-prototype';a=r/'experiments/d9-rc-scalar-readiness-reuse-20260927';a.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def put(src,target=None,compress=False):
 src=Path(src);dst=a/(target or src.name);dst.parent.mkdir(parents=True,exist_ok=True);data=src.read_bytes();dst.write_bytes(gzip.compress(data,mtime=0) if compress else data)
for name in ['measure.py','validate.py','traps.py','embedding-final.py','gc-controls.py','lox-build.py','lox-control.py','lox-measure.py','archive.py']:
 put(w/name,'scripts/'+name)
for name in ['embedding.c','embed.my','heap-frame-size.json','embedding-final.json','gc-controls.json']:
 put(w/name)
for name in ['validation-before.json','validation-after-initial.json','validation-before-initial.json','traps-budget-probe-refusal.json','traps-stack-probe-refusal.json','lox-emission-cli-refusal.json']:
 put(w/name,('validation.json.gz' if name=='validation-before.json' else 'development/'+name+'.gz'),True)
for p in w.glob('*.log'):put(p,'logs/'+p.name+'.gz',True)
put(w/'controls/results.json','controls.json.gz',True)
for p in (w/'controls').glob('*emitted.json.gz'):put(p,'emissions/'+p.name)
for p in w.glob('*emitted.json'):put(p,'emissions/'+p.name+'.gz',True)
for p in w.glob('lox-*-emitted.json.gz'):put(p,'emissions/'+p.name)
put(w/'lox-emission.json','lox-emission.json.gz',True)
put(w/'lox/builds.json','lox-builds.json.gz',True)
if (w/'lox-results.json').exists():put(w/'lox-results.json','lox-results.json')
put(r/'tests/lang/rc_append_loops.my');put(r/'tests/lang/rc_plain_appends.my')
prior=r/'experiments/d9-rc-native-type-facts-20260927'
for name in ['accepted-gc-reference.json','accepted-gc-identities.json','accepted-gc-observations.json']:
 put(prior/name)
for name in ['binary_trees.tree.lox','expected-n10.txt']:put(prior/name)
guest=r/'.tmp-mut-argument/type-facts/measure/guest';(a/'lox-source.json.gz').write_bytes(gzip.compress(json.dumps({str(p.relative_to(guest)):p.read_text() for p in guest.rglob('*.my')},sort_keys=True).encode(),mtime=0))
paths=['src/qbe_cow.zig','src/qbe_rc_append.zig','src/qbe_rc_append_test.zig','src/qbe_rc_frame.zig','src/qbe_rc_nonheld_capture.zig','src/qbe_rc_state.zig','src/qbe_rc_append_loop.zig','src/rc_append_loop.zig','tests/lang/rc_append_loops.my','SPEC.md']
patch=subprocess.run(['git','diff','HEAD','--',*paths],capture_output=True,check=True).stdout
for path in paths:
 if subprocess.run(['git','ls-files','--error-unmatch',path],capture_output=True).returncode:
  patch+=subprocess.run(['git','diff','--no-index','--','/dev/null',path],capture_output=True).stdout
(a/'source.patch.gz').write_bytes(gzip.compress(patch,mtime=0))
compilers={'before':r.parent/'d9-rc-readiness-before-astra/.tmp-readiness/install/bin/mylang','after':w/'install/bin/mylang'}
identity={'before_source':subprocess.run(['git','rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip(),'compilers':{k:{'path':str(p),'sha256':sha(p)} for k,p in compilers.items()},'production_files':{p:sha(r/p) for p in paths if p.startswith('src/')},'patch_sha256':hashlib.sha256(patch).hexdigest(),'cpu':3,'harness_sha256':sha(w/'embedding'),'harness_header_sha256':sha(r/'src/native_rc_internal.h')}
(a/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
print(a)
