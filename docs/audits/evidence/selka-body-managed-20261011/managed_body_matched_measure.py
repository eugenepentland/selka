import hashlib, json, os, subprocess, sys
from pathlib import Path
root=Path("/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang")
scratch=Path("/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots")
script=root/"selfhost/tests/measure_managed_body_adoption.py"
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
expected="20fb7facf405ff440f38703d9c600ed9cbd74af904fbeba5a45571bc159ea273"
if digest(scratch/"body-check-release/bin/mylang") != expected: raise RuntimeError("frozen baseline host changed")
if sorted(os.sched_getaffinity(0)) != [2,3,10,11]: raise RuntimeError("timing affinity differs")
if "/gate" not in os.readlink("/proc/self/fd/30"): raise RuntimeError("outer gate FD30 absent")
receipt={"status":"running","affinity":sorted(os.sched_getaffinity(0)),"measurement_script_sha256":digest(script),"qualification_script_sha256":digest(root/"selfhost/tests/run_body_check_qualification.py"),"runs":[]}
receipt_path=scratch/"body-managed/body-managed-timing-receipt.json"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
configurations = [
 ("baseline",scratch/"body-check-release",scratch/"body-managed-baseline-source",["--baseline"]),
 ("candidate",scratch/"body-managed-release",root,[])]
for phase in ("prewarm", "timed"):
 for label,prefix,source,extra in configurations:
  command=[sys.executable,str(script),"--isolated","--label",label,"--zig","/home/epentland/.local/bin/zig","--compiler",str(prefix/"bin/mylang"),"--builder",str(prefix/"tools/selka-components"),"--component-dir",str(prefix/"libexec/mylang/components"),"--source-root",str(source),"--output",str(scratch/("body-managed/body-managed-"+phase+"-"+label+".json"))]+extra+(["--prewarm-only"] if phase=="prewarm" else [])
  print("START "+label,flush=True)
  run={"label":label,"phase":phase,"command":command,"host_sha256":digest(prefix/"bin/mylang"),"source_root":str(source)}
  result=subprocess.run(command,pass_fds=(30,))
  run["exit_status"]=result.returncode
  receipt["runs"].append(run)
  if result.returncode:
   receipt["status"]="failed";receipt_path.write_text(json.dumps(receipt,indent=2)+"\n");raise SystemExit(result.returncode)
  output=scratch/("body-managed/body-managed-"+phase+"-"+label+".json")
  run["output_sha256"]=digest(output)
  receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
  print("DONE "+label,flush=True)
receipt["status"]="completed"
receipt_path.write_text(json.dumps(receipt,indent=2)+"\n")
