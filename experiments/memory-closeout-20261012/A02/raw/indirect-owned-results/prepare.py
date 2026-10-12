from pathlib import Path
import hashlib,json,subprocess,sys
root=Path.cwd();here=Path(__file__).resolve().parent;out=root/".tmp/memory-closeout/A02/indirect-owned-results"
compiler=root/".zig-cache/o/996ba6e9ee40f947c47a9f97fbc2ef69/mylang"
source=root/"src/core/a02_indirect_owned_fixture.my"
result={"compiler":str(compiler),"compiler_sha256":hashlib.sha256(compiler.read_bytes()).hexdigest(),"steps":[]}
def run(argv):
    p=subprocess.run(list(map(str,argv)),capture_output=True,text=True,timeout=90)
    result["steps"].append({"argv":list(map(str,argv)),"status":p.returncode,"stdout":p.stdout,"stderr":p.stderr})
    return p
p=run([compiler,"fmt",source])
assert p.returncode==0
source.write_text(p.stdout);(here/"sources/indirect_owned.my").write_text(p.stdout)
result["fixture_sha256"]=hashlib.sha256(source.read_bytes()).hexdigest()
p=run([compiler,"build",source,"--experimental-zero-rc","--release","--cache-dir",out/"baseline-cache","-o",out/"baseline-program"])
result["expected_refusal"]=p.returncode==1 and "E_ZERO_RC_LOWERING" in p.stderr
(out/"baseline.json").write_text(json.dumps(result,indent=2)+"\n")
assert result["expected_refusal"]
raise SystemExit(subprocess.run([sys.executable,here/"registered.py"]).returncode)
