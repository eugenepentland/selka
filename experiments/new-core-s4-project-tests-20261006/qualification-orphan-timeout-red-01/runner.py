import sys,os,json,subprocess
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests/experiments/new-core-s4-project-tests-20261006')
import qualification_support as support
area=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests/experiments/new-core-s4-project-tests-20261006/qualification-orphan-timeout-red-01')
(area/"runner.pid").write_text(str(os.getpid()))
import faulthandler,signal
faulthandler.register(signal.SIGUSR1)
def traced(frame,event,argument):
    if event == "exception" and frame.f_code.co_filename == support.__file__ and argument[0] is subprocess.TimeoutExpired:
        error=argument[1]
        (area/"inner-timeout.stdout").write_bytes(error.stdout or b"")
        (area/"inner-timeout.stderr").write_bytes(error.stderr or b"")
    return traced
sys.settrace(traced)
print("runner started",flush=True)
try:
    support.Capture(area/"processes",area).run([sys.executable,str(area/"fixture.py")],capture_output=True,timeout=0.3)
except subprocess.TimeoutExpired as error:
    (area/"returned.stdout").write_bytes(error.stdout or b"")
    (area/"returned.stderr").write_bytes(error.stderr or b"")
    print("cleanup returned",flush=True)
