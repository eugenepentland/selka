#!/usr/bin/env python3
"""Bind linked LLVM code size and backward-branch placement across four groups."""
import argparse, hashlib, importlib.util, json, re, shutil, subprocess
from pathlib import Path
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True)
p.add_argument('--native',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
helper=ROOT/'experiments/runtime-goal110-bounded-rem-llvm-20261004/compare-executables.py'
s=importlib.util.spec_from_file_location('images',helper);images=importlib.util.module_from_spec(s);s.loader.exec_module(images)
def artifact(path):
 path=Path(path).resolve();return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size)
def capture(name,command):
 done=subprocess.run(command,capture_output=True,text=True,check=True)
 path=a.output/name;path.write_text(done.stdout)
 return dict(command=command,status=done.returncode,stdout=artifact(path),stderr=done.stderr),done.stdout
manifests={label:images.manifest(path) for label,path in [('before',a.before),('after',a.after)]}
assert manifests['before'][1]['source_revision']=='1a3980631e79bc65f048acd063d7250800f01901'
assert manifests['after'][1]['source_revision']=='5818cee8e679c1f30fd5966963210511fcf69919'
report=dict(status='running',utc=datetime.now(timezone.utc).isoformat(),runner=artifact(__file__),elf_helper=artifact(helper),
 manifests={label:binding for label,(value,binding) in manifests.items()},tools={name:artifact(shutil.which(name)) for name in ('nm','objdump','size')},groups={},native_ir=[],
 limitations=['Backward branch targets are machine-code observations, not a reconstructed dominance proof or a claim every target has a hint.',
 '32byte alignment metadata requests at most31padding bytes per honored machine-loop header; LLVM may transform/clone loops.',
 'Range facts may change instructions and shared placement; no unique caller-address cause or performance claim.'])
for group in images.GROUPS:
 rows={}
 for label,(document,binding) in manifests.items():
  binary=Path(document['identity']['binary_paths'][group+'/my-llvm']);sidecar=Path(str(binary)+'.qbe-manifest.json')
  assert artifact(binary)['sha256']==document['binary_hashes'][group+'/my-llvm']
  policy=json.loads(sidecar.read_text());assert policy['backend']=='llvm' and policy['optimization']=='3' and policy['lto'] and not policy['thin_lto']
  nm_record,nm=capture(group+'-'+label+'.nm',['nm','-S','--defined-only',str(binary)])
  asm_record,assembly=capture(group+'-'+label+'.asm',['objdump','-d','--no-show-raw-insn',str(binary)])
  size_record,sizes=capture(group+'-'+label+'.size',['size','-A',str(binary)])
  defined={line.split()[-1]:(int(line.split()[0],16),int(line.split()[1],16)) for line in nm.splitlines() if len(line.split())==4}
  function_headers=list(re.finditer(r'^([0-9a-f]+) <([^>]+)>:\n',assembly,re.M))
  bodies={m[2]:assembly[m.end():function_headers[i+1].start() if i+1<len(function_headers) else len(assembly)] for i,m in enumerate(function_headers)}
  functions=[]
  for function in policy['functions']:
   symbol=function['symbol'];entry=defined.get(symbol)
   if entry is None:
    functions.append(dict(name=function['name'],symbol=symbol,linked=False));continue
   start,count=entry;instructions=[]
   for match in re.finditer(r'^\s*([0-9a-f]+):\s+(\S+)\s*(.*)$',bodies[symbol],re.M):
    address=int(match[1],16)
    if start<=address<start+count:instructions.append((address,match[2],match[3]))
   backwards=[];nop_bytes=0
   for i,(address,opcode,operands) in enumerate(instructions):
    end=instructions[i+1][0] if i+1<len(instructions) else start+count
    if re.search(r'\bnop[a-z]*\b',opcode+' '+operands):nop_bytes+=end-address
    target=re.match(r'([0-9a-f]+)\s',operands)
    if opcode.startswith('j') and target and start<=int(target[1],16)<=address:
     value=int(target[1],16);backwards.append(dict(branch=address,target=value,mod32=value%32,mod64=value%64,opcode=opcode))
   headers=sorted({row['target'] for row in backwards})
   functions.append(dict(name=function['name'],symbol=symbol,linked=True,entry=start,size=count,instructions=len(instructions),nop_bytes=nop_bytes,
    backward_branches=backwards,unique_backward_targets=headers,targets_aligned32=sum(x%32==0 for x in headers)))
  elf=images.elf(binary);text=elf[2]['.text'][0]
  rows[label]=dict(binary=artifact(binary),sidecar=artifact(sidecar),nm=nm_record,assembly=asm_record,size=size_record,
   text_address=text[2],text_bytes=text[4],functions=functions,guest_function_bytes=sum(f.get('size',0) for f in functions),guest_nop_bytes=sum(f.get('nop_bytes',0) for f in functions))
 delta=rows['after']['text_bytes']-rows['before']['text_bytes']
 report['groups'][group]=dict(arms=rows,text_delta_bytes=delta,text_ratio=rows['after']['text_bytes']/rows['before']['text_bytes'])
 print(group,'text',rows['before']['text_bytes'],'->',rows['after']['text_bytes'],'delta',delta,'guest-nop',rows['before']['guest_nop_bytes'],'->',rows['after']['guest_nop_bytes'],flush=True)
# The actual native O3/fullLTO builds preserve translated IL/IR under receipt-bound build commands.
native=json.loads((a.native/'native-differential.json').read_text());assert native['status']=='passed'
for build in native['builds']:
 if build['arm']!='after' or '-llvm-' not in build['config']:continue
 binary=Path(build['binary']['path']);policy=json.loads(Path(build['manifest']['path']).read_text())
 for function in policy['functions']:
  symbol=function['symbol'];ssa=binary.parent/'dump'/(symbol+'.ssa');ir=binary.parent/'dump'/(symbol+'.ll')
  assert ssa.is_file() and ir.is_file();text=ir.read_text();markers=ssa.read_text().count('# myl-floor-result')
  assert markers==text.count('call void @llvm.assume')
  report['native_ir'].append(dict(config=build['config'],name=function['name'],il=artifact(ssa),ir=artifact(ir),markers=markers,
    loop_attachments=text.count(', !llvm.loop !'),align32_payloads=text.count('!"llvm.loop.align", i32 32')))
assert any(row['align32_payloads'] for row in report['native_ir'])
assert any(row['markers'] for row in report['native_ir'])
for label,(value,binding) in manifests.items():images.manifest(Path(binding['path']))
report.update(status='passed',native_report=artifact(a.native/'native-differential.json'))
(a.output/'code-proof.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS linked LLVM sizes/backedges for all4groups and actual native translated range/alignment metadata')
