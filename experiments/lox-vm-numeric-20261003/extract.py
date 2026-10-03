#!/usr/bin/env python3
"""Verify frozen tools/source/ELFs and extract actual numeric SSA/assembly."""
from pathlib import Path
import hashlib,json,re,subprocess
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-vm-numeric-20261003';borrow=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-borrow-assert-20261003/.tmp-lox-borrow-assert-20261003')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();files=lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
baseline=json.loads((borrow/'static-builds.json').read_text());final=json.loads((work/'builds.json').read_text());frozen=json.loads((work/'source-final.json').read_text());assert baseline['verified_after'] and final['verified_after'];assert baseline['source37']==frozen['baseline'];assert files(Path(final['source']))==frozen['candidate'];assert files(Path(baseline['source']))==frozen['baseline']
compiler=Path(final['compiler']);qbe=compiler.with_name('qbe');assert sha(compiler)==final['compiler_sha256']==baseline['compiler_sha256']['fixed'];assert sha(qbe)==final['qbe_sha256']==baseline['qbe_sha256']
rows={};commands=[]
for arm in ['baseline','v1']:
 q=baseline['builds']['fixed-qbe'] if arm=='baseline' else next(row for row in final['runs'] if row['runtime']=='rc' and row['backend']=='qbe')
 binaries={b:Path(baseline['builds']['fixed-'+b]['binary'] if arm=='baseline' else next(row for row in final['runs'] if row['runtime']=='rc' and row['backend']==b)['binary']) for b in ['qbe','llvm']}
 cache=Path(q['cache']);manifest=next(cache.glob('modules/*/out/vm.manifest.json'));doc=json.loads(manifest.read_text());rows[arm]={'manifest':str(manifest),'manifest_sha256':sha(manifest),'functions':{},'binary_sha256':{b:sha(p) for b,p in binaries.items()}}
 for function in doc['functions']:
  if function['name'] not in ['vm::numeric','vm::run']:continue
  paths=list((cache/'frontend/fragments').rglob(function['il_digest']));assert paths and len({sha(p) for p in paths})==1;il=paths[0].read_text();name=function['name'].split('::')[-1]
  out=work/(arm+'-'+name+'.ssa')
  if out.exists():assert out.read_text()==il
  else:out.write_text(il)
  row={'symbol':function['symbol'],'ssa_sha256':sha(out),'ssa_lines':len(il.splitlines()),'managed_sites':{op:len(re.findall('_rcg_'+op+r'\b',il)) for op in ['take','drop','loan','unloan','copy']},'backends':{}}
  for backend,binary in binaries.items():
   argv=['objdump','-d','--no-show-raw-insn','--disassemble='+function['symbol'],str(binary)];assembly=subprocess.check_output(argv,text=True);commands.append({'argv':argv,'binary_sha256':sha(binary)})
   # The header includes the actual build path. Save final extraction separately
   # from first v1 receipts rather than replacing that historical header.
   asmout=work/(arm+'-'+name+'.'+backend+'.final.asm');assert not asmout.exists();asmout.write_text(assembly)
   row['backends'][backend]={'assembly':str(asmout),'sha256':sha(asmout),'instructions':len(re.findall(r'^\s*[0-9a-f]+:\s+',assembly,re.M)),'calls':len(re.findall(r':\s+call\s',assembly))}
  rows[arm]['functions'][function['name']]=row
for b in ['qbe','llvm']:assert sha(work/('v1-'+b))==rows['v1']['binary_sha256'][b]
qpaths=json.loads((work/'paths.json').read_text());lpaths=json.loads((work/'llvm-paths.json').read_text())
for receipt in [qpaths,lpaths]:
 for arm,data in receipt['arms'].items():
  for op,row in data.items():
   suffix='.path.asm' if receipt is qpaths else '.llvm-tail.asm';assert sha(work/(arm+'-'+op+suffix))==row['path_sha256']
result={'source37':frozen,'compiler':str(compiler),'compiler_sha256':sha(compiler),'qbe_sha256':sha(qbe),'controls_build_receipt':str(borrow/'static-builds.json'),'controls_build_receipt_sha256':sha(borrow/'static-builds.json'),'build_receipt_sha256':sha(work/'builds.json'),'arms':rows,'commands':commands,'qbe_paths':qpaths,'llvm_tails':lpaths,'final_rc_elf_equals_v1_both_backends':True,'llvm_numeric_symbol_absent_due_to_inlining':True,'verified_after':files(Path(final['source']))==frozen['candidate'] and files(Path(baseline['source']))==frozen['baseline'],'meaning':'static instruction and call sites only; explicit path assumptions; no timing/performance samples'}
(work/'static-final.json').write_text(json.dumps(result,indent=2)+'\n');print('Both frozen source37/toolchains/RC_ELFs verified; QBE complete helper paths, LLVM inlined tails preserved')
