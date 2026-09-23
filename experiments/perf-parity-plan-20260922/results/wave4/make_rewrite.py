#!/usr/bin/env python3
"""Copy the audit's rewrite/counterfactual tools and add a `framesk` category:
drop the frame record link, metadata and position slot but keep the stack-floor
guard (whose probe is the record allocation)."""
import pathlib
import shutil

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = ROOT / "experiments/perf-parity-plan-20260922"
for name in ("rewrite_il.py", "counterfactual.py"):
    shutil.copy(SRC / name, HERE / name)
p = HERE / "rewrite_il.py"
t = p.read_text()
a = "        if 'F' in mode:\n            if skip_until:"
assert a in t
t = t.replace(a, "        if 'F' in mode or 'K' in mode:\n            if skip_until:")
b = "            if re.match(r' %v\\d+ =l add %ctx, 64$', L):\n                skip_until = '@stackadmit'"
assert b in t
t = t.replace(b, "            if 'F' in mode and re.match(r' %v\\d+ =l add %ctx, 64$', L):\n                skip_until = '@stackadmit'")
c = "        elif c == 'positions':"
t = t.replace(c, "        elif c == 'framesk':\n            mode += 'K'\n" + c)
p.write_text(t)
c = HERE / "counterfactual.py"
ct = c.read_text()
old = "HERE = Path(__file__).resolve().parent\nROOT = HERE.parents[1]"
assert old in ct
ct = ct.replace(old, f"HERE = Path(__file__).resolve().parent\nROOT = Path({str(SRC)!r}).parents[1]")
c.write_text(ct)
print("ok")
