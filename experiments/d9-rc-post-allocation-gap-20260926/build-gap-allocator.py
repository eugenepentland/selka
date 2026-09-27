import concurrent.futures,hashlib,json,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent
compilers={"rc":p/"install-gap-allocator/bin/mylang", "gc":Path("/home/epentland/ai/canopy/mylang-worktrees/d9-physical-borrow-after-astra/.tmp-physical/install-accepted/bin/mylang")}
assert hashlib.sha256(compilers["gc"].read_bytes()).hexdigest()=="8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478"
commands=[]
for backend in ("qbe","llvm"):
 for mode in ("rc","stats","gc"):
  for suffix in (("n12",) if mode=="stats" else ("n12","repeat")):
   source=p/("binary_trees_n12_repeat.my" if suffix=="repeat" else "binary_trees_n12.my")
   compiler=compilers["gc" if mode=="gc" else "rc"]
   command=[str(compiler),"build",str(source),"-o",str(p/f"gap-allocator-{backend}-{mode}-{suffix}"),"--cache-dir",str(p/f"cache-gap-allocator-{backend}-{mode}"),"--keep-symbols"]
   if mode!="gc":command += ["--rc-runtime=stats" if mode=="stats" else "--rc-runtime"]
   if backend=="llvm":command += ["--backend=llvm","--llvm-opt=3","--lto"]
   commands.append(command)
(p/"gap-allocator-commands.json").write_text(json.dumps(commands,indent=2)+"\n")
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 for result in pool.map(lambda cmd:subprocess.run(cmd,check=True),commands):pass
