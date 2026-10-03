#!/usr/bin/env python3
"""Replay a bytecode overlay onto the exact accepted combined84 source."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',type=Path,default=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-next/combined'))
p.add_argument('--variant',choices=['octets-v1','octets-v2','octets-shape-v3'],default='octets-shape-v3')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();here=Path(__file__).resolve().parent
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=lambda d:{str(f.relative_to(d)):sha(f) for f in sorted(d.rglob('*')) if f.is_file()}
manifest=json.loads((here/'sources.json').read_text())
assert files(a.base)==manifest['control37']
assert not a.output.exists()
shutil.copytree(a.base,a.output)
patch=here/(a.variant+'.patch')
subprocess.run(['git','apply','--no-index',str(patch.resolve())],cwd=a.output,check=True)
assert files(a.output)==manifest[a.variant]['source37']
print(a.output.resolve(),a.variant,'all37 hashes verified')
