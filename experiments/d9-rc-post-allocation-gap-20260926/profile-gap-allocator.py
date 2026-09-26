import hashlib,json,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent
expected=(p/'rc-n12.stdout').read_text()*240
commands=[]
for backend in ('qbe','llvm'):
 for mode in ('rc','gc'):
  name=f'gap-allocator-{backend}-{mode}-repeat';data=p/(name+'.data')
  cmd=['perf','record','-q','-e','cpu_core/instructions/u','-F','199','-o',str(data),'--','taskset','-c','2',str(p/name)]
  commands.append(cmd)
  done=subprocess.run(cmd,text=True,capture_output=True,check=True)
  assert done.stdout==expected,(backend,mode)
  with (p/(name+'.profile.txt')).open('w') as f:subprocess.run(['perf','report','--stdio','--no-children','--sort','symbol,dso','--percent-limit','0.3','-i',str(data),'--dsos',name],stdout=f,check=True)
  with (p/(name+'.samples.txt')).open('w') as f:subprocess.run(['perf','script','-i',str(data),'-F','ip,sym,dso,period','--dsos',name],stdout=f,check=True)
  print(name,flush=True)
(p/'gap-allocator-profile-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
