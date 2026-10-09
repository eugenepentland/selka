#!/usr/bin/env python3
"""Exact source-bound Core comparison; retain every command and raw output."""
import hashlib
import json
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[3]
base = pathlib.Path(__file__).resolve().parent
compiler = pathlib.Path(sys.argv[1]).resolve()
label = sys.argv[2]
paths = sorted(p for p in (root / 'tests/lang').glob('*.my') if ' in range(' in p.read_text())
rows = []
for path in paths:
    outdir = base / label / path.stem
    outdir.mkdir(parents=True, exist_ok=True)
    modes = [('raw', []), ('facts', ['--facts'])]
    for mode, flags in modes:
        argv = [str(compiler), 'dump-ir', str(path), *flags]
        before = time.monotonic()
        result = subprocess.run(argv, cwd=root, capture_output=True)
        (outdir / f'{mode}.stdout').write_bytes(result.stdout)
        (outdir / f'{mode}.stderr').write_bytes(result.stderr)
        rows.append(dict(source=str(path.relative_to(root)), source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), mode=mode, argv=argv, exit=result.returncode, wall_seconds=time.monotonic()-before, output_sha256=hashlib.sha256(result.stdout).hexdigest()))
manifest = dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=rows)
(base / f'{label}.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps({'label': label, 'commands': len(rows), 'passed': sum(row['exit']==0 for row in rows)}))
