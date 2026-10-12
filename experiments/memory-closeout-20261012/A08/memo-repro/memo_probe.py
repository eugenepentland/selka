import pathlib,json,shutil,subprocess,os,hashlib
root=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012-A08')
work=root/'.tmp/memory-closeout/A08/memo-probe-01';work.mkdir(exist_ok=False)
out=root/'experiments/memory-closeout-20261012/A08/memo-probe-01';out.mkdir(exist_ok=False)
a05=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012-A05/.tmp/memory-closeout/A05')
cache=a05/'support7-memo-repro/fresh-cache'
source=a05/'support7-full/batch-04/memo/debug/source/main.my'
base=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator')
rows=[]
for name,compiler,parts in [('rf-full',base/'support7-install/bin/mylang',None),('debug-full',base/'support7-debug-install/bin/mylang',None),('rf-front',base/'support7-install/bin/mylang',['frontend','semantic']),('rf-stages',base/'support7-install/bin/mylang',['stages-packed-v1']),('rf-syntax',base/'support7-install/bin/mylang',['frontend'])]:
 p=work/name;p.mkdir();c=p/'cache';c.mkdir()
 for x in cache.iterdir():
  if parts is not None and x.name not in parts:continue
  if x.is_dir():shutil.copytree(x,c/x.name)
  else:shutil.copy2(x,c/x.name)
 argv=[str(compiler),'build',str(source),'--experimental-zero-rc','--cache-dir',str(c),'--zig',os.environ['ZIG'],'--unoptimized','--counters','-o',str(p/'program'),'--emit-llvm',str(p/'program.ll'),'--report']
 result=subprocess.run(argv,cwd=root,capture_output=True,text=True,timeout=120,env=dict(os.environ,MYLANG_COMPILER_SHARED_CACHE=''))
 row=dict(name=name,argv=argv,status=result.returncode,stdout=result.stdout,stderr=result.stderr,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),cache_parts=parts)
 rows.append(row);(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n');(out/(name+'.stderr')).write_text(result.stderr);print(name,result.returncode,flush=True)
