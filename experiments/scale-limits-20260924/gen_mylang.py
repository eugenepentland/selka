import sys
from pathlib import Path
sys.path.insert(0, "/home/epentland/ai/canopy/mylang/.claude/worktrees/agent-a61eea1742b770d52/experiments/build-loop-20260924")
import gen_scale

root = Path(__file__).resolve().parent
for name, modules in (("t200k", 480), ("t500k", 1200), ("t1m", 2400)):
    gen_scale.mylang(root / name, modules, 38)
    print(name, sum(p.stat().st_size for p in (root / name / "mylang").glob("*.my")))
