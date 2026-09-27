import collections,hashlib,importlib.util,json,subprocess
from pathlib import Path
root=Path.cwd(); work=root/'.tmp-rc-performance/ownership-schematic-profile'
spec=importlib.util.spec_from_file_location('measurement',root/'experiments/d9-rc-ownership-joined-20260927/measurement_core.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
joined=json.loads((root/'.tmp-rc-performance/ownership-joined-e5d47d20/results.json').read_text())
program=next(p for p in joined['identity']['programs'] if p['id']=='schematic/fixture')
repeat=root.parent/'d9-rc-integration/experiments/d9-rc-flat-borrow-joined-20260927/repeat.py'
result={'identity':joined['identity'],'diagnostic_only':True,'profiles':{}}
for backend in ('qbe','llvm'):
 binary=root/'.tmp-rc-performance/ownership-joined-e5d47d20/bin'/('schematic.'+backend)
 assert m.A.sha(binary)==joined['builds']['schematic.'+backend]['sha256']
 run=m.PC.run_spec(program,binary,'ownership-profile-'+backend,joined['schematic_declared'])
 data=work/(backend+'.data')
 cmd=['taskset','-c','2','perf','record','-e','cpu_core/instructions/u','-c','20000033','-o',str(data),'--','python3',str(repeat),'100',m.PC.SCHEMATIC_SVG['fixture'],*run['argv']]
 done=subprocess.run(cmd,cwd=run['cwd'],env=run['env'],capture_output=True,timeout=120)
 assert done.returncode==0,(done.returncode,done.stderr)
 rec={'command':cmd,'status':done.returncode,'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'binary_sha256':m.A.sha(binary),'data_sha256':m.A.sha(data)}
 for name,cmd in [('report',['perf','report','-i',str(data),'--stdio','--sort','symbol','--percent-limit','0.5']),('raw',['perf','script','-D','-i',str(data)]),('samples',['perf','script','-i',str(data),'-F','period,ip,sym,dso'])]:
  parsed=subprocess.run(cmd,capture_output=True,check=True);(work/(backend+'.'+name+'.txt')).write_bytes(parsed.stdout);rec[name+'_stderr']=parsed.stderr.decode()
 raw=(work/(backend+'.raw.txt')).read_text(); rec['throttle_records']=raw.count('PERF_RECORD_THROTTLE');rec['unthrottle_records']=raw.count('PERF_RECORD_UNTHROTTLE')
 result['profiles'][backend]=rec
 (work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
 print(backend,'completed; throttle records',rec['throttle_records'],flush=True)
