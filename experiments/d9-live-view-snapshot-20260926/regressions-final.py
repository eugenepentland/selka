import pathlib,subprocess,json,os,hashlib,re
r=pathlib.Path.cwd();d=r/'.tmp-rc/view-snapshot';c=r/'.tmp-rc/install-view-snapshot-final/bin/mylang';results=[]
sources=['tests/lang/live_view_snapshots.my','tests/lang/dictionary_views.my','tests/lang/rc_dictionary_views.my','tests/lang/rc_view_receivers.my','tests/lang/iteration_identity.my','tests/lang/collection_read_callbacks.my']
work=d/'guests';work.mkdir(exist_ok=True);cases=[];imports=[];hashes={}
for i,source in enumerate(sources):
 text=(r/source).read_text();module=f'case_{i}';text=re.sub(r'^module \w+',f'module {module}',text,count=1)
 if not text.startswith('module '):text=f'module {module}\n'+text
 (work/f'{module}.my').write_text(text);imports.append(module);hashes[source]=hashlib.sha256((r/source).read_bytes()).hexdigest();cases += [module+'.'+fn for fn in re.findall(r'public def (test_\w+)\(',text)]
entry=work/'driver.my';entry.write_text('module driver\n'+'\n'.join('import '+s for s in imports)+'\n\ndef main() -> int:\n'+''.join('    assert '+c+'()\n' for c in cases)+'    return 0\n')
for backend in ['qbe','llvm']:
 for mode in ['gc','rc']:
  cmd=['scripts/build-slot.sh','build',str(c),'build',str(entry),'--backend',backend,'--mode','ReleaseFast','--cache-dir',str(d/'regression-cache'),'--run']+(['--gc-stress'] if mode=='gc' else ['--rc-runtime=stats'])+(['--llvm-opt','3','--lto'] if backend=='llvm' else [])
  x=subprocess.run(cmd,env=os.environ|{'TMPDIR':str(r/'.tmp-rc/tmp')},capture_output=True,text=True,timeout=300)
  lines=[z for z in x.stderr.splitlines() if z.startswith('MYLANG_RC_COUNTS ')];counts=json.loads(lines[0].split(' ',1)[1]) if len(lines)==1 else None
  passed=x.returncode==0 and (mode=='gc' or counts is not None and counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'])
  results.append(dict(compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),source_hashes=hashes,cases=cases,backend=backend,mode=mode,cmd=cmd,status=x.returncode,stdout=x.stdout,stderr=x.stderr,counts=counts,passed=passed));(d/'regressions-final.json').write_text(json.dumps(results,indent=2));print(backend,mode,len(cases),passed,counts,flush=True)
