import os,subprocess,sys
from pathlib import Path
Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests/experiments/new-core-s4-project-tests-20261006/qualification-orphan-timeout-red-01/command.pid').write_text(str(os.getpid()))
subprocess.Popen([sys.executable,"-c",'import os,time\nfrom pathlib import Path\nPath(\'/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests/experiments/new-core-s4-project-tests-20261006/qualification-orphan-timeout-red-01/descendant.pid\').write_text(str(os.getpid()))\nos.write(1,b"orphan-partial\\xff\\n")\ntime.sleep(30)\n'],start_new_session=True)
os._exit(0)
