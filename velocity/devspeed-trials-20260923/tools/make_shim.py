import sys, os, stat
real, log, dest = sys.argv[1:4]
os.makedirs(os.path.dirname(dest), exist_ok=True)
open(dest, "w").write(f'''#!/usr/bin/env python3
import json, os, subprocess, sys, time
t0 = time.time()
p = subprocess.run([{real!r}] + sys.argv[1:], capture_output=True)
dt = time.time() - t0
sys.stdout.buffer.write(p.stdout); sys.stdout.flush()
sys.stderr.buffer.write(p.stderr); sys.stderr.flush()
try:
    with open({log!r}, "a") as f:
        f.write(json.dumps({{"ts": t0, "argv": sys.argv[1:], "cwd": os.getcwd(), "exit": p.returncode, "dur": round(dt, 3),
            "stdout": p.stdout[:1500].decode("utf-8", "replace"), "stderr": p.stderr[:4000].decode("utf-8", "replace")}}) + "\\n")
except OSError:
    pass
sys.exit(p.returncode)
''')
os.chmod(dest, 0o755)
