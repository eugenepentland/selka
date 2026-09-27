#!/usr/bin/env python3
"""Collect terminal named-home-only measurements without rebuilding anything."""
from pathlib import Path
import gzip, hashlib, json, shutil, subprocess
root=Path.cwd();work=root/'.tmp-mut-argument/field-list-read';out=Path(__file__).resolve().parent;old=root/'experiments/d9-rc-record-field-read-20260927';controls=work/'controls'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def packed(source,name):
 data=source.read_bytes();(out/name).write_bytes(gzip.compress(data,mtime=0) if name.endswith('.gz') and not source.name.endswith('.gz') else data)
for source,name in [(work/'paired-results.json','paired-results.json.gz'),(work/'candidate-builds.json','builds-after.json.gz'),(work/'builds.json','builds-before.json.gz'),(work/'final-emitted.json.gz','emitted-after.json.gz'),(work/'final-vm-run.il','vm-run-after.il.gz'),(work/'final-emission-command.json','emission-command.json'),(work/'measure-paired.log','measurement.log'),(work/'focused-rc.log','focused-rc.log')]:packed(source,name)
for name in ('accepted-gc-identities.json','accepted-gc-observations.json','expected-n10.txt','binary_trees.tree.lox','identity.json','current-vm-run.il.gz'):
 packed(old/name,'before-identity.json' if name=='identity.json' else 'vm-run-before.il.gz' if name=='current-vm-run.il.gz' else name)
for name in ('guests.json','embedding.json','prototype-guests.json','prototype-embedding.json','embedding-small-leaf-attempt.json'):
 packed(controls/name,name+'.gz')
for name in ('prepare.py','embed.py','embedding.c','driver.my','fixture-seven-tests.my','driver-seven-tests.my','prepare-final.log','embed-final.log'):
 packed(controls/name,name)
for side in ('before','after'):
 for mode in ('plain','accounted'):packed(controls/(side+'-'+mode+'.json.gz'),side+'-'+mode+'.json.gz')
for name in ('measure-paired.py','build-candidate.py'):packed(work/name,name)
packed(root/'tests/lang/rc_record_field_reads.my','fixture.my')
assert not subprocess.check_output(['git','diff','49c6ca07bbba8b35cda4436b831327ac40c8fc87','HEAD','--','src'])
patch=subprocess.check_output(['git','diff','--cached','--binary','HEAD','--','src','SPEC.md','tests/lang/rc_record_field_reads.my'])
(out/'implementation.patch').write_bytes(patch)
changed=subprocess.check_output(['git','diff','--cached','--name-only','--','src']).decode().splitlines()
identity={'base':'49c6ca07bbba8b35cda4436b831327ac40c8fc87','head_before_patch':subprocess.check_output(['git','rev-parse','HEAD']).decode().strip(),'patch_sha256':sha(out/'implementation.patch'),'compiler':str(work/'install-final/bin/mylang'),'compiler_sha256':sha(work/'install-final/bin/mylang'),'production_and_test_sources':{name:sha(root/name) for name in changed},'control_sources':{str(root/'tests/lang/rc_record_field_reads.my'):sha(root/'tests/lang/rc_record_field_reads.my')},'embedding_driver':{'path':str(controls/'embedding'),'sha256':sha(controls/'embedding')}}
(out/'identity-after.json').write_text(json.dumps(identity,indent=2)+'\n')
summary=json.loads((work/'paired-results.json').read_text())['summary'];(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('archived',len(list(out.iterdir())),'files')
