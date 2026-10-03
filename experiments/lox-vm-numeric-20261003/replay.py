#!/usr/bin/env python3
"""Copy an exact selected baseline, apply the experiment and verify source37."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
p=argparse.ArgumentParser(description=__doc__);p.add_argument('baseline',type=Path);p.add_argument('destination',type=Path);a=p.parse_args()
exp=Path(__file__).resolve().parent;manifest=json.loads((exp/'sources.json').read_text());sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest();files=lambda root:{str(f.relative_to(root)):sha(f) for f in sorted(root.rglob('*')) if f.is_file()}
assert files(a.baseline)==manifest['baseline'];assert not a.destination.exists();shutil.copytree(a.baseline,a.destination)
with (exp/'numeric.patch').open('rb') as patch:subprocess.run(['patch','--batch','--fuzz=0','-p1'],cwd=a.destination,stdin=patch,check=True)
assert files(a.destination)==manifest['candidate'];print('Exact37-file numeric87 overlay reconstructed')
