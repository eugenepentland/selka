import pathlib,re,json,subprocess,os,hashlib
r=pathlib.Path.cwd();w=r/'.tmp/rc-read-captures/broad';w.mkdir(exist_ok=True);c=r/'.tmp/rc-read-captures/install/bin/mylang';rows=[];cases=[];imports=[];hashes={}
names=['collection_read_callbacks','rc_read_loans','rc_owned_values','rc_view_receivers','rc_temporary_lifetimes','rc_dictionary_views','dictionary_views']
for i,name in enumerate(names):
 p=r/'tests/lang'/f'{name}.my';text=p.read_text();hashes[name]=hashlib.sha256(text.encode()).hexdigest();text=re.sub(r'^module \w+',f'module capture_{i}',text,count=1)
 if not text.startswith('module '):text=f'module capture_{i}\n'+text
 (w/f'capture_{i}.my').write_text(text);imports.append(f'capture_{i}');cases += [f'capture_{i}.{x}()' for x in re.findall(r'public def (test_\w+)\(\)',text)]
p=w/'main.my';p.write_text('module main\n'+''.join('import '+x+'\n' for x in imports)+'\ndef main() -> int:\n'+''.join('    assert '+x+'\n' for x in cases)+'    return 0\n')
for mode in ['gc','rc']:
 for backend in ['qbe','llvm']:
  out=w/(mode+'-'+backend);cmd=['scripts/build-slot.sh','build',str(c),'build',str(p),'--backend',backend,'--mode','ReleaseFast','--cache-dir='+str(w/'cache'),'-o',str(out)]
  if mode=='rc':cmd+=['--rc-runtime=stats']
  if backend=='qbe':cmd+=['--qbe='+str(c.parent/'qbe')]
  else:cmd+=['--llvm-opt','3','--lto']
  b=subprocess.run(cmd,capture_output=True,text=True);row=dict(mode=mode,backend=backend,command=cmd,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),source_hashes=hashes,cases=cases,build_exit=b.returncode,build_log=b.stdout+b.stderr)
  if b.returncode==0:
   x=subprocess.run([str(out)],capture_output=True,text=True,env={**os.environ,'MYLANG_OPTIONS':'--gc-stress'},timeout=300);row.update(exit=x.returncode,stdout=x.stdout,stderr=x.stderr,binary_sha256=hashlib.sha256(out.read_bytes()).hexdigest());row['passed']=x.returncode==0
  else:row['passed']=False
  rows.append(row);(w/'results.json').write_text(json.dumps(rows,indent=2));print(mode,backend,len(cases),row['passed'],row.get('stderr'),flush=True)
  if not row['passed']:print(row,flush=True);raise SystemExit(1)
