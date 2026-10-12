#!/usr/bin/env python3
"""Inventory every current guest fixture; launch under build admission."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import re
p=argparse.ArgumentParser()
p.add_argument("--compiler",type=Path,required=True)
p.add_argument("--output",type=Path,required=True)
p.add_argument("--cache",type=Path,required=True)
a=p.parse_args()
rows=[]
compiler=a.compiler.resolve()
# Mirror local imports/assets. Library entries get the same inert main used by
# the guest test runner, without modifying original fixture bytes.
mirror=a.cache.resolve().parent / "survey-sources"
mirror.mkdir(parents=True,exist_ok=True)
shutil.copytree("tests", mirror / "tests", dirs_exist_ok=True)
for root in [Path("tests/lang"),Path("tests/value_semantics")]:
    for source in sorted(root.rglob("*.my")):
        checked=mirror / source
        original=source.read_text()
        stubbed=not re.search(r"^(?:public )?(?:func|def) main\(",original,re.M)
        if stubbed: checked.write_text(original + "\n\nfunc main() -> int:\n    return 0\n")
        cmd=[str(compiler),"check",str(checked),"--experimental-zero-rc","--cache-dir",str(a.cache)]
        result=subprocess.run(cmd,capture_output=True,text=True)
        rows.append(dict(source=str(source),checked_source=str(checked),stubbed=stubbed,sha256=hashlib.sha256(source.read_bytes()).hexdigest(),status=result.returncode,stdout=result.stdout,stderr=result.stderr))
        if len(rows)%25==0: print("checked",len(rows),flush=True)
counts=dict(Counter(str(row["status"]) for row in rows))
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(dict(compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),counts=counts,results=rows),indent=2)+"\n")
print(json.dumps(counts),flush=True)
