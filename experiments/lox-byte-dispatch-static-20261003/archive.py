#!/usr/bin/env python3
"""Preserve exact read-only bytecode diagnostics; never executes guest binaries."""
from pathlib import Path
import difflib,gzip,hashlib,json
OWN=Path(__file__).resolve().parents[2];OUT=Path(__file__).resolve().parent
STATIC=OWN/'.tmp-lox-byte-static-20261003';PROTOTYPE=OWN/'.tmp-lox-byte-dispatch-20261003'
ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-byte-screen-ready')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();read=lambda p:json.loads(Path(p).read_text());files=lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
source=read(PROTOTYPE/'u8-if-v2-source.json');builds=read(PROTOTYPE/'builds.json');assert builds['verified_after']
assert source['candidate37']==files(PROTOTYPE/'u8-if-v2')==builds['source37'];assert source['baseline37']==files(Path(source['baseline_source']))
assert [k for k in source['candidate37'] if source['candidate37'][k]!=source['baseline37'][k]]==['vm.my']
configuration=read(ROOT/'binaries.json');extraction=read(STATIC/'extraction.json');prototype=read(PROTOTYPE/'static.json');attribution=read(STATIC/'path-attribution.json')
for arm,row in extraction.items():
 assert row['binary_sha256']==sha(configuration['binaries'][arm])==configuration['binary_sha256'][arm]
 assert row['linked_manifest_sha256']==sha(configuration['binaries'][arm]+'.qbe-manifest.json')
 for name,f in row['functions'].items():
  assert sha(f['il_source'])==f['il_sha256']
  assert sha(STATIC/(arm+'-'+name.split('::')[-1]+'.asm'))==f['assembly_sha256']
for row in builds['runs']:
 assert row['status']==0 and sha(row['binary'])==row['binary_sha256']
 assert sha(row['binary']+'.qbe-manifest.json')==row['manifest_sha256']
 assert sha(row['binary']+'.qbe-receipt')==row['receipt_sha256']
for backend,row in prototype.items():
 assert row['binary_sha256']==sha(PROTOTYPE/('u8-if-v2-'+backend))
 for name,f in row['functions'].items():
  assert sha(f['il_source'])==f['il_sha256']
  assert sha(PROTOTYPE/(backend+'-'+name.split('::')[-1]+'.asm'))==f['assembly_sha256']
  reference=extraction['octets-'+backend]['functions'][name]
  assert (f['instructions'],f['calls'])==(reference['instructions'],reference['calls'])
assert attribution['case_current_sha256']==sha(attribution['case']['script'])==attribution['case']['script_sha256']
assert attribution['sweep_sha256']==sha(ROOT/'measurements/instruction-screen.json')
assert attribution['analysis_sha256']==sha(ROOT/'instruction-analysis.json')
old=Path(source['baseline_source'])/'vm.my';new=PROTOTYPE/'u8-if-v2/vm.my'
patch=''.join(difflib.unified_diff(old.read_text().splitlines(True),new.read_text().splitlines(True),fromfile='a/vm.my',tofile='b/vm.my'))
(OUT/'u8-if-rejected.patch').write_text(patch)
raw={}
for directory,label in [(STATIC,'frozen-diagnostic'),(PROTOTYPE,'prototype')]:
 for p in sorted(directory.iterdir()):
  if p.is_file() and p.suffix in ['.py','.json','.ssa','.asm','.log']:
   raw[label+'/'+p.name]=p.read_text()
raw['prototype/u8-if-v2/vm.my']=new.read_text()
for row in builds['runs']:
 binary=Path(row['binary'])
 for suffix in ['.qbe-manifest.json','.qbe-receipt']:
  raw['prototype/'+binary.name+suffix]=Path(str(binary)+suffix).read_text()
encoded=json.dumps(raw,sort_keys=True,separators=(',',':')).encode();target=OUT/'receipts.json.gz';target.write_bytes(gzip.compress(encoded,mtime=0));assert gzip.decompress(target.read_bytes())==encoded
summary={'source_only_author_commit':'beaaf97c7397beafb0988f5ed73dde0bf4813ebb','selected_compiler_sha256':builds['compiler_sha256'],'selected_qbe_sha256':builds['qbe_sha256'],'source':source,'frozen_elf_emission_extraction':extraction,'path_attribution':attribution,'prototype_builds':builds,'prototype_static':prototype,'outcome':'Rejected: direct u8 comparison source has no static instruction/call reduction and preserves the extra LLVM dispatch move. No new behavior tests or perf.','archive_sha256':sha(target),'archive_raw_files':len(raw),'archive_files_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in raw.items()},'prototype_patch_sha256':sha(OUT/'u8-if-rejected.patch'),'verified_after':True,'limits':['Native disassembly is from exact frozen ELF hashes; generic IL inspected here is the corresponding QBE checked module emission, not newly generated LLVM IR.','Static repeat model excludes bookkeeping/startup/other optimization changes and is a near attribution, not exact dynamic execution tracing.','Whole-body native instruction/call totals are identical; relocated addresses can differ and no byte-identical guest claim is made.','37 opcode constants are checked narrow casts; unknown opcode continuation, numeric argument widening, IP order and all operand helpers remain unchanged.','Preparation v1 failed only a comparison-count assertion before candidate edits/builds; its baseline copy and failure receipt are preserved.']}
(OUT/'review.json').write_text(json.dumps(summary,indent=2)+'\n');print('Frozen diagnostics, source-only rejected prototype and exact static attribution archived; no guests executed.')
