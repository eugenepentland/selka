#!/usr/bin/env python3
"""Complete one admitted external gate batch; every phase has its own receipt."""
from pathlib import Path
import json
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
worktree = root.parents[1]
timer = root / "tools/time-command.py"
refs = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-integration/experiments/frontend-current-lang-oracle-20261008")
integration = refs.parents[1]
compiler_source = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-fb1")
compiler = compiler_source / "zig-out/bin/mylang"
scratch = worktree / ".mylang-cache/frontend-fb1-external"
identities = json.loads((root / "input-identities.json").read_text())
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")


def phase(label, *argv):
    print("starting " + label, flush=True)
    done = subprocess.run([sys.executable, str(timer), label, "--", *map(str, argv)], cwd=worktree, env=env)
    if done.returncode:
        raise SystemExit(done.returncode)
    print("passed " + label, flush=True)


for corpus, count in (("lox", 974), ("eda", 34)):
    phase("archive-fb1-" + corpus + "-native-evidence", sys.executable, root / "tools/archive-native-evidence.py",
        "--area", scratch / "native-results" / corpus, "--output", root / ("native-" + corpus),
        "--cases", str(count))
print("native archives passed", flush=True)
