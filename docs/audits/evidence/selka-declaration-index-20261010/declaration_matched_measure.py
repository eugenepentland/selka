import hashlib, json, os, subprocess, sys
from pathlib import Path
root=Path("/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang")
scratch=Path("/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots")
script=root/"selfhost/tests/measure_declaration_adoption.py"
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
expected="4f41c951fa3dd9e5b2b6f17e12cc958d91e3858734f1a3439549e4b3211bdfec"
if digest(scratch/"hardening-release/bin/mylang") != expected: raise RuntimeError("frozen baseline host changed")
if sorted(os.sched_getaffinity(0)) != [2,3,10,11]: raise RuntimeError("timing affinity differs")
if "/gate" not in os.readlink("/proc/self/fd/30"): raise RuntimeError("outer gate FD30 absent")
receipt={"status":"running","affinity":sorted(os.sched_getaffinity(0)),"measurement_script_sha256":digest(script),"qualification_script_sha256":digest(root/"selfhost/tests/run_declaration_qualification.py"),"runs":[]}
receipt_path=scratch/"declaration-timing-receipt.json"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
for label,prefix,source,extra in [
 ("baseline",scratch/"hardening-release",scratch/"hardening-baseline-source",["--baseline"]),
 ("candidate",scratch/"declaration-release",root,[])]:
 command=[sys.executable,str(script),"--isolated","--label",label,"--zig","/home/epentland/.local/bin/zig","--compiler",str(prefix/"bin/mylang"),"--builder",str(prefix/"tools/selka-components"),"--component-dir",str(prefix/"libexec/mylang/components"),"--source-root",str(source),"--output",str(scratch/("declaration-timing-"+label+".json"))]+extra
 print("START "+label,flush=True)
 run={"label":label,"command":command,"host_sha256":digest(prefix/"bin/mylang"),"source_root":str(source)}
 result=subprocess.run(command,pass_fds=(30,))
 run["exit_status"]=result.returncode
 receipt["runs"].append(run)
 if result.returncode:
  receipt["status"]="failed";receipt_path.write_text(json.dumps(receipt,indent=2)+"\n");raise SystemExit(result.returncode)
 output=scratch/("declaration-timing-"+label+".json")
 run["output_sha256"]=digest(output)
 receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
 print("DONE "+label,flush=True)
receipt["status"]="completed"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
