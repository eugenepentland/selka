#!/usr/bin/env python3
"""Verify the full LLVM emission and allocated RC/GC guest bytes."""
from pathlib import Path
import hashlib,importlib.util,json
from prefixes import snapshot
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-native-policy-20261003'
root=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
borrow=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-borrow-assert-20261003/.tmp-lox-borrow-assert-20261003')
oldast=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003/.tmp-lox-ast-carrier-20261003')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
frozen=json.loads((work/'frozen-source-complete.json').read_text());builds=json.loads((work/'builds-complete.json').read_text());assert builds['verified_after']
for name,h in frozen['core'].items():assert sha(lane/name)==h
assert {str(p.relative_to(Path(frozen['source']))):sha(p) for p in sorted(Path(frozen['source']).rglob('*')) if p.is_file()}==frozen['source37']
before=snapshot()
helper=root/'experiments/lox-compiler-screen-20261003/elf.py';spec=importlib.util.spec_from_file_location('elf',helper);elf=importlib.util.module_from_spec(spec);spec.loader.exec_module(elf)
report={'complete_source_descriptor_sha256':sha(work/'frozen-source-complete.json'),'compiler_sha256':builds['compiler_sha256'],'helper_sha256':sha(helper),'immutable_prefixes_before':before,'comparisons':{},'verified_after':False}
first=work/'llvm-final-emission.stdout';second=work/'llvm-control-emission.stdout';assert first.read_bytes()==second.read_bytes();manifest=json.loads(first.read_text());assert len(manifest['functions'])==420
report['llvm_all420']={'full_manifest_il_and_metadata_equal':True,'raw_sha256':sha(first),'per_unit_sha256':{f['name']:hashlib.sha256(f['il'].encode()).hexdigest() for f in manifest['functions']}}
for runtime,backend in [('rc','llvm'),('gc','llvm'),('gc','qbe')]:
 row=next(r for r in builds['runs'] if r['runtime']==runtime and r['backend']==backend)
 for p,h in row['artifacts_sha256'].items():assert sha(p)==h
 candidate=Path(row['binary'])
 if runtime=='rc':control=borrow/'fixed-llvm-ast';receipt=borrow/'static-builds.json'
 else:
  receipt=oldast/('build-fixed-'+backend+'-gc')/(backend+'-gc.json');v=json.loads(receipt.read_text());assert v['source_files']==frozen['source37'] and v['compiler_sha256']=='d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040';assert v['source_verified_after'] and v['compiler_verified_after'];control=Path(v['binary']);assert sha(control)==v['binary_sha256']
 result=elf.compare(candidate,control);result.update(candidate=str(candidate),control=str(control),control_build_receipt=str(receipt),control_build_receipt_sha256=sha(receipt))
 report['comparisons'][runtime+'-'+backend]=result
 for p,h in frozen['core'].items():assert sha(lane/p)==h
report['immutable_prefixes_after']=snapshot();assert before==report['immutable_prefixes_after'];report['verified_after']=True
(work/'equivalence.json').write_text(json.dumps(report,indent=2)+'\n');print('Full420 IL+metadata identical; LLVM RC/GC and QBE GC allocated sections/program layout exact')
