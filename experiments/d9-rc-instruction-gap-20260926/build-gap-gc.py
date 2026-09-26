import concurrent.futures,json,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent
commands=[]
for backend in ('qbe','llvm'):
 cmd=[str(p/'install-gap/bin/mylang'),'build',str(p/'binary_trees_n12.my'),'-o',str(p/('gap-'+backend+'-gc-n12')),'--cache-dir',str(p/('cache-gap-'+backend)),'--keep-symbols']
 if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
 commands.append(cmd)
(p/'gap-gc-build-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 for result in pool.map(lambda cmd:subprocess.run(cmd,check=True),commands):pass
