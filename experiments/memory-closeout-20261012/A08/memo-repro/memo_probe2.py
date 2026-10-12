import pathlib,json,shutil,subprocess,os
root=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012-A08');first=root/'.tmp/memory-closeout/A08/memo-probe-01';work=root/'.tmp/memory-closeout/A08/memo-probe-02';work.mkdir(exist_ok=False);out=root/'experiments/memory-closeout-20261012/A08/memo-probe-02';out.mkdir(exist_ok=False)
meta=json.loads((root/'experiments/memory-closeout-20261012/A08/memo-probe-01/semantic-inventory.json').read_text());base=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator');source='/home/epentland/ai/canopy/mylang-memory-20261012-A05/.tmp/memory-closeout/A05/support7-full/batch-04/memo/debug/source/main.my';rows=[]
cases=[('debug-warm',None),('rf-fn',[x for x in meta if x['key'].startswith('fn')]),('rf-spec',[x for x in meta if x['key'].startswith('spec')]),('rf-sym',[x for x in meta if x['key'].startswith('sym')])]+[('rf-one-'+x['file'].split('/')[-1][:10],[x]) for x in meta if x['key'].startswith('fn')]
for name,selected in cases:
 p=work/name;p.mkdir();c=p/'cache';compiler=base/('support7-debug-install' if selected is None else 'support7-install')/'bin/mylang'
 if selected is None:shutil.copytree(first/'debug-full/cache',c)
 else:
  for x in selected:
   target=c/'semantic'/x['file'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(first/'rf-front/cache/semantic'/x['file'],target)
 argv=[str(compiler),'build',source,'--experimental-zero-rc','--cache-dir',str(c),'--zig',os.environ['ZIG'],'--unoptimized','--counters','-o',str(p/'program'),'--emit-llvm',str(p/'program.ll'),'--report']
 r=subprocess.run(argv,cwd=root,capture_output=True,text=True,timeout=120,env=dict(os.environ,MYLANG_COMPILER_SHARED_CACHE=''));rows.append(dict(name=name,argv=argv,status=r.returncode,stdout=r.stdout,stderr=r.stderr,selected=selected));(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n');print(name,r.returncode,flush=True)
