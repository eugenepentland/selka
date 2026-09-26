import concurrent.futures,json,subprocess,sys
from pathlib import Path
p=Path(__file__).resolve().parent
arms=['gap']
commands=[]
for arm in arms:
 for backend in ('qbe','llvm'):
  for mode in ('rc','gc'):
   cmd=[str(p/('install-'+arm+'/bin/mylang')),'build',str(p/'binary_trees_n12_repeat.my'),'-o',str(p/(arm+'-'+backend+'-'+mode+'-repeat')),'--cache-dir',str(p/('cache-'+arm+'-'+backend)),'--keep-symbols']
   if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime']
   commands.append(cmd)
(p/'gap-repeat-build-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 jobs=[pool.submit(subprocess.run,cmd,check=True) for cmd in commands]
 for job in jobs:job.result()
