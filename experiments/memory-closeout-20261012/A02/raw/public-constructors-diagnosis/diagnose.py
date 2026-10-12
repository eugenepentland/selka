import hashlib,json,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parent
compiler=Path("/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support6-install/bin/mylang")
results={"compiler_source":"5167c588be79dd43d21d5013c36db15110bf239b","compiler_path":str(compiler),"compiler_sha256":hashlib.sha256(compiler.read_bytes()).hexdigest(),"cases":{}}
for source in sorted((root/"sources").glob("*.my")):
 row={"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest()}
 for label,args in [("check",["check",str(source),"--experimental-zero-rc"]),("typed",["dump-typed",str(source),"main"])]:
  if label=="typed" and source.stem in ["sets","generator_arguments"]:continue
  argv=[str(compiler),*args]; start=time.monotonic(); p=subprocess.run(argv,capture_output=True,text=True,timeout=20)
  row[label]={"argv":argv,"status":p.returncode,"elapsed_admitted_seconds":time.monotonic()-start,"stdout":p.stdout,"stderr":p.stderr}
  if label=="typed":(root/(source.stem+".typed")).write_text(p.stdout)
 results["cases"][source.stem]=row
(root/"results.json").write_text(json.dumps(results,indent=2)+"\n")
print(json.dumps({k:v["check"]["status"] for k,v in results["cases"].items()}))
