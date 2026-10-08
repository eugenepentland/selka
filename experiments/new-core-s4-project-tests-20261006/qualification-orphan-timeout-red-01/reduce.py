import ctypes,errno,json,os,signal,subprocess,sys,time,hashlib
from pathlib import Path
area=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests/experiments/new-core-s4-project-tests-20261006/qualification-orphan-timeout-red-01')
ctypes.CDLL(None,use_errno=True).prctl(36,1,0,0,0)
began=time.monotonic()
p=subprocess.Popen([sys.executable,str(area/"runner.py")],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,env=dict(os.environ,PYTHONDONTWRITEBYTECODE="1"))
failed=False
try:
    out,err=p.communicate(timeout=2)
except subprocess.TimeoutExpired as error:
    failed=True
    os.kill(p.pid,signal.SIGUSR1)
    time.sleep(0.02)
    out,err=error.stdout or b"",error.stderr or b""
    ids={name:int((area/(name+".pid")).read_text()) for name in ("runner","command","descendant") if (area/(name+".pid")).exists()}
    for pid in ids.values():
        try: os.kill(pid,signal.SIGKILL)
        except ProcessLookupError: pass
    remaining_out,remaining_err=p.communicate()
    out,err=remaining_out,remaining_err
    for pid in ids.values():
        try: os.waitpid(pid,0)
        except ChildProcessError: pass
else:
    ids={name:int((area/(name+".pid")).read_text()) for name in ("runner","command","descendant") if (area/(name+".pid")).exists()}
(area/"outer.stdout").write_bytes(out)
(area/"outer.stderr").write_bytes(err)
receipt={"helper_sha256":hashlib.sha256((area.parent/"qualification_support.py").read_bytes()).hexdigest(),"capture_timeout":0.3,"outer_timeout":2,"outer_timed_out":failed,"fixture_pids":ids,"elapsed_seconds":time.monotonic()-began,"runner_status":p.returncode,"raw_stdout_hex":out.hex(),"raw_stderr_hex":err.hex(),"all_fixture_processes_reaped":True}
(area/"summary.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps(receipt))
raise SystemExit(0 if failed else 1)
