from pathlib import Path
import gzip,hashlib,json,subprocess,shutil
r=Path.cwd();w=r/'.tmp-mut-argument/caller-field-read';out=r/'experiments/d9-rc-caller-field-read-implementation-20260927';out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def put(p,name=None,compress=False):
 p=Path(p);name=name or p.name;q=out/(name+('.gz' if compress else ''));q.write_bytes(gzip.compress(p.read_bytes(),mtime=0) if compress else p.read_bytes())
for name in ('candidate-builds.json','paired-results.json','emission-sites.json'):put(w/name,compress=True)
put(r/'.tmp-mut-argument/field-list-read/proof-final-builds.json','builds-before.json',True)
for name in ('build-candidate.py','measure-paired.py','archive.py','build-prototype-fixed.log','focused-fixed.log','focused-rc.log','build-candidate.log','measure-paired.log','emitted.json.gz'):
 p=w/name
 if p.exists():put(p)
for name in ('prepare.py','embed.py','embedding.c','driver.my','prepare-final.log','embedding-complete.log','guests.json','embedding.json','before-plain.json.gz','before-accounted.json.gz','after-plain.json.gz','after-accounted.json.gz'):
 put(w/'controls'/name,compress=name.endswith('.json'))
for p in (w/'controls').glob('rejected-*'):put(p,compress=p.suffix=='.json')
for name in ('expected-n10.txt','accepted-gc-observations.json','accepted-gc-identities.json','binary_trees.tree.lox'):put(r/'experiments/d9-rc-record-field-read-implementation-20260927'/name)
files=['SPEC.md','src/qbe_rc_record_read.zig','src/qbe_rc_record_read_plan.zig','src/qbe_rc_record_read_test.zig','src/qbe_rc_record_read_anchor.zig','src/rc_field_authority.zig','src/rc_record_read.zig','src/root_test.zig','tests/lang/rc_caller_field_reads.my']
patch=subprocess.check_output(['git','diff','fa9e4cd5','--',*files])
if not (out/'identity.json').exists():(out/'implementation.patch').write_bytes(patch)
builds=json.loads((w/'candidate-builds.json').read_text());before=json.loads((r/'.tmp-mut-argument/field-list-read/proof-final-builds.json').read_text())
identity={'base':'fa9e4cd5','before_source':'c1224f30','compiler':builds['compiler'],'compiler_sha256':builds['compiler_sha256'],'before_compiler':before['compiler'],'before_compiler_sha256':before['compiler_sha256'],'guest':builds['builds'][0]['cwd'],'sources':builds['sources'],'production_and_test_sources':{x:sha(r/x) for x in files},'patch_sha256':sha(out/'implementation.patch'),'embedding_driver':{'path':str(w/'controls/embedding'),'sha256':sha(w/'controls/embedding')}}
if not (out/'identity.json').exists():(out/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
a=json.loads(gzip.decompress((w/'emitted.json.gz').read_bytes()))
old_path=r/'experiments/d9-rc-record-field-read-implementation-20260927/emitted-after.json.gz'
put(old_path,'project-before.json.gz')
old=json.loads(gzip.decompress(old_path.read_bytes()))
old_bodies={f['name']:f['il'] for f in old['functions']}
for f in a['functions']:
 if f['name'] in ('vm::read_byte','vm::read_short','vm::read_constant','vm::make_closure','vm::run'):
  (out/(f['name'].replace('::','-')+'-after.il.gz')).write_bytes(gzip.compress(f['il'].encode(),mtime=0))
  (out/(f['name'].replace('::','-')+'-before.il.gz')).write_bytes(gzip.compress(old_bodies[f['name']].encode(),mtime=0))
# Frozen measured artifacts above remain unchanged; corrected proof is bridged.
(out/'final-source.patch').write_bytes(patch)
fixed=w/'install-proof-final/bin/mylang'
correction={'compiler':str(fixed),'compiler_sha256':sha(fixed),'patch_sha256':sha(out/'final-source.patch'),'sources':{x:sha(r/x) for x in files}}
(out/'proof-correction-identity.json').write_text(json.dumps(correction,indent=2)+'\n')
for name in ('proof-final-builds.json','proof-controls.json'):put(w/name,compress=True)
for name in ('guardian-full.log','guardian-command-refusal.log','focused-proof-final.log','build-proof-final.log','build-proof-final-guests.log','proof-controls.log','build-proof-final-guests.py','proof-controls.py'):put(w/name)
checks={str(p.relative_to(out)):sha(p) for p in out.rglob('*') if p.is_file() and p.name not in ('archive-sha256.json','README.md','verify.py')}
(out/'archive-sha256.json').write_text(json.dumps(checks,indent=2)+'\n');print(len(checks),'archive files')
