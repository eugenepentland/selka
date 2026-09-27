import bisect,collections,concurrent.futures,importlib.util,json,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-rc-performance/ownership-schematic-profile'
spec=importlib.util.spec_from_file_location('measurement',root/'experiments/d9-rc-ownership-joined-20260927/measurement_core.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
joined=json.loads((root/'.tmp-rc-performance/ownership-joined-e5d47d20/results.json').read_text())
p=next(p for p in joined['identity']['programs'] if p['id']=='schematic/fixture')
compiler=joined['identity']['compiler']; assert m.A.sha(compiler)==joined['identity']['compiler_sha256']
builds={}
for backend in ('qbe','llvm'):
 out=work/('schematic.'+backend+'.symbols')
 cmd,cwd=m.PC.build_command(p,compiler,backend,out,root/'.tmp-rc-performance/ownership-joined-e5d47d20/cache')
 builds[backend]={'bin':out,'cmd':[str(root/'scripts/build-slot.sh'),'build',*cmd,'--rc-runtime','--keep-symbols'],'cwd':cwd}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 results=dict(zip(builds,pool.map(m.PC.do_build,builds.values())))
(work/'symbol-builds.json').write_text(json.dumps(results,indent=2)+'\n')
def section(binary):
 raw=binary.read_bytes(); out=subprocess.check_output(['objdump','-h',str(binary)],text=True)
 line=next(line.split() for line in out.splitlines() if len(line.split())>1 and line.split()[1]=='.text')
 size,addr,offset=(int(line[i],16) for i in (2,3,5));return addr,raw[offset:offset+size]
for backend,result in results.items():
 assert result['ok'],result
 original=root/'.tmp-rc-performance/ownership-joined-e5d47d20/bin'/('schematic.'+backend)
 binary=work/('schematic.'+backend+'.symbols')
 assert section(original)==section(binary),'text changed: cannot map symbols to measured program'
 symbols=subprocess.check_output(['nm','-S','-n',str(binary)],text=True);(work/(backend+'.nm.txt')).write_text(symbols)
 ranges=[]
 for line in symbols.splitlines():
  f=line.split()
  if len(f)==4 and f[2].lower()=='t': ranges.append((int(f[0],16),int(f[1],16),f[3]))
 starts=[x[0] for x in ranges];counts=collections.Counter();total=0
 for line in (work/(backend+'.samples.txt')).read_text().splitlines():
  f=line.split()
  if len(f)<4 or f[-1]!='('+str(original)+')':continue
  ip=int(f[1],16);at=bisect.bisect_right(starts,ip)-1;total+=1
  match=ranges[at] if at>=0 else None
  name=match[2] if match and ip<match[0]+match[1] else '[unmapped]'
  counts[name]+=1
 mapped={'text_identical':True,'samples':total,'symbols':counts.most_common(),'qualitative_only':'Every recorded event throttled; counts are not unbiased cost fractions.'}
 (work/(backend+'.mapped.json')).write_text(json.dumps(mapped,indent=2)+'\n')
 print(backend,total,counts.most_common(16),flush=True)
