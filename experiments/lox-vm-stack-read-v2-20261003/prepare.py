#!/usr/bin/env python3
"""Apply the standalone V2 overlay to exact selected AST source, without builds."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('baseline', type=Path)
p.add_argument('destination', type=Path)
a = p.parse_args()
experiment = Path(__file__).resolve().parent
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
files = lambda root: {str(f.relative_to(root)): sha(f) for f in sorted(root.rglob('*')) if f.is_file()}
expected = json.loads((experiment/'source-hashes.json').read_text())
assert files(a.baseline) == expected['source_sha256']['control']
assert not a.destination.exists()
shutil.copytree(a.baseline, a.destination)
patch = experiment/'readonly-stack-equality-inline.patch'
assert sha(patch) == expected['patch_sha256']
run = subprocess.run(['patch', '-p1', '--batch'], cwd=a.destination, input=patch.read_bytes(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert run.returncode == 0, run.stderr.decode()
assert files(a.destination) == expected['source_sha256']['inline-qualified']
print(json.dumps({'source': str(a.destination.resolve()), 'source_sha256': files(a.destination), 'patch_sha256': sha(patch)}, indent=2))
