from pathlib import Path
import json,hashlib,subprocess,sys,struct,re,datetime
root=Path.cwd();work=root/'.mylang-cache/goal110-index-forward-rf';out=work/'static';out.mkdir(exist_ok=True);h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
sys.path.insert(0,str(root/'benchmarks/runtime'));from build_compiler import validate_receipt
rf=work/'compiler-receipt.json';r=json.loads(rf.read_text());compiler=Path(r['compiler_path']);validate_receipt(r,compiler,artifacts=True);assert r['source_revision']=='14ffa2c0f385a11e5216bbdec5bdff429f9f981b'
g4=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf');control_receipt=g4/'compiler-receipt.json';cr=json.loads(control_receipt.read_text());control=Path(cr['compiler_path']);validate_receipt(cr,control,artifacts=True)
manifest=work/'runner/manifest.json';m=json.loads(manifest.read_text());cm_path=g4/'runner/manifest.json';cm=json.loads(cm_path.read_text())
report={'schema':'mylang-index-update-releasefast-static-v1','source_revision':r['source_revision'],'timing':False,'compiler_receipts':{'before':{'path':str(control_receipt),'sha256':h(control_receipt)},'after':{'path':str(rf),'sha256':h(rf)}},'tools':{arm:{'path':str(p.resolve()),'sha256':h(p)} for arm,p in [('before',control),('after',compiler)]},'manifest':{'path':str(manifest),'sha256':h(manifest)},'control_manifest':{'path':str(cm_path),'sha256':h(cm_path)},'binary_hashes':m['binary_hashes'],'frontend':{},'code':{}}
for name,path in m['identity']['binary_paths'].items():assert h(path)==m['binary_hashes'][name]
(out/'before-invocation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'tools':report['tools'],'compiler_receipts':report['compiler_receipts']}),flush=True)
for arm,c in [('before',control),('after',compiler)]:
 source=root/'benchmarks/runtime/ports/main.my';command=[str(c),'emit-project-qbe',str(source),'--rc-runtime','--drop-step-checks','--drop-frame-checks','--native-variants=qbe-v2','--no-cache'];done=subprocess.run(command,cwd=root,capture_output=True);(out/f'ports-{arm}.json').write_bytes(done.stdout);(out/f'ports-{arm}.stderr').write_bytes(done.stderr);assert done.returncode==0
 v=json.loads(done.stdout);f=next(f for f in v['functions'] if f['name']=='main::main');il=f['il'];(out/f'ports-{arm}-main.ssa').write_text(il);markers=[line.strip() for line in il.splitlines() if '# RC-INDEX-UPDATE-1' in line]
 assert len(markers)==(0 if arm=='before' else 4);assert 'PREPRODUCTION' not in il
 report['frontend'][arm]={'command':command,'source_sha256':h(source),'path':str(out/f'ports-{arm}.json'),'sha256':h(out/f'ports-{arm}.json'),'markers':markers}
for name in ['legacy/my-llvm','compute/my-llvm']:
 report['code'][name]={}
 for arm,saved in [('before',cm),('after',m)]:
  artifact=Path(saved['identity']['binary_paths'][name]);assert h(artifact)==saved['binary_hashes'][name]
  meta=Path(str(artifact)+'.qbe-manifest.json');q=json.loads(meta.read_text());assert q['backend']=='llvm' and q['optimization']=='3' and q['lto'] and not q['thin_lto'];entry=next(f for f in q['functions'] if f['name']=='main::main');symbol=entry['symbol'];nm=subprocess.check_output(['nm','-S','--defined-only',str(artifact)],text=True);line=next(l for l in nm.splitlines() if l.split()[-1]==symbol);address,size=(int(x,16) for x in line.split()[:2]);asm=subprocess.check_output(['objdump','-d','--no-show-raw-insn','--disassemble='+symbol,str(artifact)],text=True);dest=out/(name.replace('/','-')+'-'+arm+'.asm');dest.write_text(asm)
  data=artifact.read_bytes();shoff=struct.unpack_from('<Q',data,40)[0];ents,count,names=struct.unpack_from('<HHH',data,58);headers=[struct.unpack_from('<IIQQQQIIQQ',data,shoff+i*ents) for i in range(count)];stringh=headers[names];strings=data[stringh[4]:stringh[4]+stringh[5]];text=next(x for x in headers if strings[x[0]:strings.find(b'\0',x[0])]==b'.text')
  report['code'][name][arm]={'path':str(artifact),'sha256':h(artifact),'entry_symbol':symbol,'entry_address':hex(address),'entry_size':size,'assembly_path':str(dest),'assembly_sha256':h(dest),'text_size':text[5],'text_sha256':hashlib.sha256(data[text[4]:text[4]+text[5]]).hexdigest(),'native_metadata_sha256':h(meta)}
assert report['code']['legacy/my-llvm']['after']['entry_size']==16365
for name,path in m['identity']['binary_paths'].items():assert h(path)==m['binary_hashes'][name]
for arm,c in [('before',control),('after',compiler)]:assert h(c)==report['tools'][arm]['sha256']
report['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();(out/'receipt.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'markers':report['frontend']['after']['markers'],'code':report['code']}),flush=True)
