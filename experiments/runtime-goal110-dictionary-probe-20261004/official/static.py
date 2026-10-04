from pathlib import Path
import datetime, hashlib, json, re, struct, subprocess, sys
root=Path.cwd();work=root/'.mylang-cache/goal110-dict-probe-debug';out=work/'static';out.mkdir(exist_ok=True)
before=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-rf-20261004/.mylang-cache/goal110-index-forward-rf')
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
sys.path.insert(0,str(root/'benchmarks/runtime'));from build_compiler import validate_receipt
manifests={k:p/'runner/manifest.json' for k,p in [('before',before),('after',work)]};ms={k:json.loads(p.read_text()) for k,p in manifests.items()}
report={'schema':'mylang-dictionary-probe-optimized-static-v1','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_revision':'64fb7e62732db9cea46414248fd59ba362e31b56','timing':False,'manifests':{k:{'path':str(p),'sha256':h(p)} for k,p in manifests.items()},'tools':{},'frontend':{},'code':{},'groups':[]}
for side,p in [('before',before),('after',work)]:
 receipt=p/'compiler-receipt.json';r=json.loads(receipt.read_text());tool=Path(r['compiler_path']);validate_receipt(r,tool,artifacts=True)
 report['tools'][side]={'path':str(tool),'sha256':h(tool),'source_revision':r['source_revision'],'receipt_path':str(receipt),'receipt_sha256':h(receipt)}
 for name,path in ms[side]['identity']['binary_paths'].items():assert h(path)==ms[side]['binary_hashes'][name]
(out/'before.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'tools':report['tools'],'manifests':report['manifests']}),flush=True)
for side in ['before','after']:
 command=[report['tools'][side]['path'],'emit-project-qbe',str(root/'benchmarks/runtime/expanded/collections/main.my'),'--rc-runtime','--drop-step-checks','--drop-frame-checks','--native-variants=qbe-v2','--no-cache']
 done=subprocess.run(command,cwd=root,capture_output=True);(out/(side+'-frontend.json')).write_bytes(done.stdout);(out/(side+'-frontend.stderr')).write_bytes(done.stderr);assert done.returncode==0
 doc=json.loads(done.stdout);units={f['name']:f['il'] for f in doc['functions']};report['frontend'][side]={'command':command,'path':str(out/(side+'-frontend.json')),'sha256':h(out/(side+'-frontend.json')),'units':{name:hashlib.sha256(il.encode()).hexdigest() for name,il in units.items()}}
report['frontend_identical']=report['frontend']['before']['units']==report['frontend']['after']['units'];assert report['frontend_identical']
for side in ['before','after']:
 artifact=Path(ms[side]['identity']['binary_paths']['collections/my-llvm']);meta=json.loads(Path(str(artifact)+'.qbe-manifest.json').read_text());assert meta['backend']=='llvm' and meta['optimization']=='3' and meta['lto'] and not meta['thin_lto']
 nm=subprocess.check_output(['nm','-S','--defined-only',str(artifact)],text=True)
 report['code'][side]={}
 for name in ['read_walk','contains_walk','myl_native_dictionary_read']:
  line=next(x for x in nm.splitlines() if x.split()[-1]==name);address,size=(int(x,16) for x in line.split()[:2]);asm=subprocess.check_output(['objdump','-d','--no-show-raw-insn','--disassemble='+name,str(artifact)],text=True);path=out/(name+'-'+side+'.asm');path.write_text(asm)
  rows=[x.strip() for x in asm.splitlines() if re.match(r'\s*[0-9a-f]+:\s',x)]
  window=[]
  if name != 'myl_native_dictionary_read':
   marker=next(i for i,x in enumerate(rows) if re.search(r'movl\s+\$0x1,0xf8\(%\w+\)',x));window=rows[max(0,marker-4):marker+5]
  report['code'][side][name]={'path':str(artifact),'sha256':h(artifact),'address':hex(address),'size':size,'assembly_path':str(path),'assembly_sha256':h(path),'found_publication_window':window} if name!='myl_native_dictionary_read' else {'path':str(artifact),'sha256':h(artifact),'address':hex(address),'size':size,'assembly_path':str(path),'assembly_sha256':h(path)}
# The matched publication retains required key/entry/state and loses its zeroing stores.
for name in ['read_walk','contains_walk']:
 b='\n'.join(report['code']['before'][name]['found_publication_window']);a='\n'.join(report['code']['after'][name]['found_publication_window'])
 assert '0xe0(' in a and '0xe8(' in a and '0xf8(' in a
 assert '0xf0(' in b and 'vxorps' in b and '0xfc(' in b and '0x108(' in b
 assert '0xf0(' not in a and 'vxorps' not in a and '0xfc(' not in a and '0x108(' not in a
report['ordinary_found_zeroing_removed']=True

def sections(path):
 d=Path(path).read_bytes();assert d[:6]==b'\x7fELF\x02\x01';off=struct.unpack_from('<Q',d,40)[0];ent,count,idx=struct.unpack_from('<HHH',d,58);hs=[struct.unpack_from('<IIQQQQIIQQ',d,off+i*ent) for i in range(count)];s=hs[idx];strings=d[s[4]:s[4]+s[5]]
 return {strings[x[0]:strings.index(b'\0',x[0])].decode():{'metadata':[x[1],x[2],x[3],x[5],x[8]],'sha256':None if x[1]==8 else hashlib.sha256(d[x[4]:x[4]+x[5]]).hexdigest()} for x in hs if x[2]&2}
for group in ['legacy','compute','collections','text']:
 for arm in ['my-llvm','my-qbe']:
  name=group+'/'+arm;parts={s:sections(ms[s]['identity']['binary_paths'][name]) for s in ['before','after']}
  report['groups'].append({'name':name,'artifacts':{s:{'path':ms[s]['identity']['binary_paths'][name],'sha256':ms[s]['binary_hashes'][name],'allocated_sections':parts[s]} for s in parts},'allocated_sections_identical':parts['before']==parts['after'],'text_identical':parts['before']['.text']==parts['after']['.text']})
for side,m in ms.items():
 for name,path in m['identity']['binary_paths'].items():assert h(path)==m['binary_hashes'][name]
 assert h(report['tools'][side]['path'])==report['tools'][side]['sha256']
report['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();(out/'receipt.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'frontend_identical':report['frontend_identical'],'zeroing_removed':True,'code':report['code'],'groups':[{k:v for k,v in row.items() if k!='artifacts'} for row in report['groups']]}),flush=True)
