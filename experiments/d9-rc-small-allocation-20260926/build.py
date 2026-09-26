import concurrent.futures,json,subprocess,sys
from pathlib import Path
p=Path(__file__).resolve().parent
arms=sys.argv[1:] or ['drop-before','flat-drop']
commands=[]
for arm in arms:
 for backend in ('qbe','llvm'):
  for mode in ('rc','stats'):
   cmd=[str(p/('install-'+arm+'/bin/mylang')),'build',str(p/'binary_trees_n12.my'),'-o',str(p/(arm+'-'+backend+'-'+mode+'-n12')),'--cache-dir',str(p/('cache-'+arm+'-'+backend)),'--rc-runtime'+('=stats' if mode=='stats' else ''),'--keep-symbols']
   if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
   commands.append(cmd)
(p/'drop-build-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 jobs=[pool.submit(subprocess.run,cmd,check=True) for cmd in commands]
 for job in jobs:job.result()
