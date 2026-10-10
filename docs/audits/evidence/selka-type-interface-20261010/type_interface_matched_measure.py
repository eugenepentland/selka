import hashlib, json, os, subprocess, sys
from pathlib import Path
root=Path("/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang")
scratch=Path("/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots")
script=root/"selfhost/tests/measure_type_interface_adoption.py"
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
expected="9d4390768195d5b2022f7cc910c753c6dbb0e0487bf965536574cf1c07feb5ee"
if digest(scratch/"declaration-release/bin/mylang") != expected: raise RuntimeError("frozen baseline host changed")
if sorted(os.sched_getaffinity(0)) != [2,3,10,11]: raise RuntimeError("timing affinity differs")
if "/gate" not in os.readlink("/proc/self/fd/30"): raise RuntimeError("outer gate FD30 absent")
receipt={"status":"running","affinity":sorted(os.sched_getaffinity(0)),"measurement_script_sha256":digest(script),"qualification_script_sha256":digest(root/"selfhost/tests/run_type_interface_qualification.py"),"runs":[]}
receipt_path=scratch/"type-interface-timing-receipt.json"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
for label,prefix,source,extra in [
 ("baseline",scratch/"declaration-release",scratch/"type-interface-baseline-source",["--baseline"]),
 ("candidate",scratch/"type-interface-release",root,[])]:
 command=[sys.executable,str(script),"--isolated","--label",label,"--zig","/home/epentland/.local/bin/zig","--compiler",str(prefix/"bin/mylang"),"--builder",str(prefix/"tools/selka-components"),"--component-dir",str(prefix/"libexec/mylang/components"),"--source-root",str(source),"--output",str(scratch/("type-interface-timing-"+label+".json"))]+extra
 print("START "+label,flush=True)
 run={"label":label,"command":command,"host_sha256":digest(prefix/"bin/mylang"),"source_root":str(source)}
 result=subprocess.run(command,pass_fds=(30,))
 run["exit_status"]=result.returncode
 receipt["runs"].append(run)
 if result.returncode:
  receipt["status"]="failed";receipt_path.write_text(json.dumps(receipt,indent=2)+"\n");raise SystemExit(result.returncode)
 output=scratch/("type-interface-timing-"+label+".json")
 run["output_sha256"]=digest(output)
 receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
 print("DONE "+label,flush=True)
receipt["status"]="completed"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
