import hashlib, json, os, subprocess, sys
from pathlib import Path
root=Path("/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang")
scratch=Path("/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots")
script=root/"selfhost/tests/measure_body_check_adoption.py"
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
expected="16d3c3bab8160aaf30ce5e9206a7259fb3d50c85d4be7b2760c65798bc161bc3"
if digest(scratch/"type-interface-release/bin/mylang") != expected: raise RuntimeError("frozen baseline host changed")
if sorted(os.sched_getaffinity(0)) != [2,3,10,11]: raise RuntimeError("timing affinity differs")
if "/gate" not in os.readlink("/proc/self/fd/30"): raise RuntimeError("outer gate FD30 absent")
receipt={"status":"running","affinity":sorted(os.sched_getaffinity(0)),"measurement_script_sha256":digest(script),"qualification_script_sha256":digest(root/"selfhost/tests/run_body_check_qualification.py"),"runs":[]}
receipt_path=scratch/"body-check/body-check-timing-receipt.json"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
for label,prefix,source,extra in [
 ("baseline",scratch/"type-interface-release",scratch/"body-check-baseline-source",["--baseline"]),
 ("candidate",scratch/"body-check-release",root,[])]:
 command=[sys.executable,str(script),"--isolated","--label",label,"--zig","/home/epentland/.local/bin/zig","--compiler",str(prefix/"bin/mylang"),"--builder",str(prefix/"tools/selka-components"),"--component-dir",str(prefix/"libexec/mylang/components"),"--source-root",str(source),"--output",str(scratch/("body-check/body-check-timing-"+label+".json"))]+extra
 print("START "+label,flush=True)
 run={"label":label,"command":command,"host_sha256":digest(prefix/"bin/mylang"),"source_root":str(source)}
 result=subprocess.run(command,pass_fds=(30,))
 run["exit_status"]=result.returncode
 receipt["runs"].append(run)
 if result.returncode:
  receipt["status"]="failed";receipt_path.write_text(json.dumps(receipt,indent=2)+"\n");raise SystemExit(result.returncode)
 output=scratch/("body-check/body-check-timing-"+label+".json")
 run["output_sha256"]=digest(output)
 receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
 print("DONE "+label,flush=True)
receipt["status"]="completed"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
