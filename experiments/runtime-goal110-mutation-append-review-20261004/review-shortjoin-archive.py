from pathlib import Path
import json,gzip,hashlib,sys,shutil,subprocess
root=Path.cwd();w=root/'experiments/runtime-goal110-join-short-20261004';p=w/'evidence.json';d=json.loads(p.read_text())
def sha(b):return hashlib.sha256(b).hexdigest()
for a in d['archive_bindings']:
 b=(w/a['archive']).read_bytes();assert sha(b)==a['archive_sha256'];raw=gzip.decompress(b) if a['archive'].endswith('.gz') else b;assert len(raw)==a['bytes'] and sha(raw)==a['raw_sha256'];assert sha(Path(a['raw']).read_bytes())==a['raw_sha256']
for group in ['script_bindings','committed_native_bindings']:
 for f,h in d[group].items():assert sha((w/f).read_bytes())==h
sys.path.insert(0,str(root/'benchmarks/runtime/expanded'));from registry import checksum
raw=root.parent/'goal110-join-short-20261004/.mylang-cache/goal110-join-short/text-guest-checks.json';q=json.loads(raw.read_text());assert q['status']=='passed';outcomes=refusals=identities=0
errors={'--max-steps=1':'R_NO_STEP_ACCOUNTING','--max-frames=1':'R_NO_FRAME_ACCOUNTING','MYLANG_MEMORY_LIMIT=1':'R_MEMORY_BUDGET'}
for c in q['checks']:
 if 'input' in c:
  case,size,it,seed=c['input'];assert checksum(case,int(size),int(it),int(seed))==c['checksum'];outcomes+=1
 elif 'binary' in c:
  fp=Path(c['binary']);assert sha(fp.read_bytes())==c['sha256'] and sha(Path(str(fp)+'.qbe-manifest.json').read_bytes())==c['manifest_sha256'];identities+=1
 else:
  assert c['error']==errors[c['control']];refusals+=1
assert (outcomes,refusals,identities)==(384,12,4)
for f in ['src/native_text.c','tests/native_text_methods_test.c']:
 assert (root/f).read_bytes()==subprocess.check_output(['git','show','448ee20c:'+f])
review=root/'benchmarks/runtime/candidates/goal110-shortjoin-448ee20c-20261004-review.json';r=json.loads(review.read_text());r['archive']={'receipt_sha256':sha(p.read_bytes()),'raw_archive_bindings':len(d['archive_bindings']),'script_bindings':len(d['script_bindings']),'native_bindings':len(d['committed_native_bindings'])};r['qualification']={'raw_sha256':sha(raw.read_bytes()),'independent_checksum_oracles':outcomes,'recorded_refusals':refusals,'live_guest_and_sidecar_bindings':identities,'limit':'guest helper asserts process success and exact output; raw rows retain checksums/refusal code, not complete process streams'};r['integrated_delta_matches_candidate_files']=['src/native_text.c','tests/native_text_methods_test.c'];r['archive_review_script_sha256']=sha(Path(__file__).read_bytes());review.write_text(json.dumps(r,indent=2)+'\n')
for n in ['review-shortjoin.py','review-shortjoin-archive.py']:shutil.copyfile(root/'.mylang-cache/goal110-review-20261004-0535'/n,root/'experiments/runtime-goal110-mutation-append-review-20261004'/n)
print({'archive':r['archive'],'qualification':r['qualification']})
