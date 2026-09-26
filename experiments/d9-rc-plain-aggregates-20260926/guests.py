"""Existing alias, aggregate-width, callback, managed-field and H controls."""
import json, os, subprocess
from pathlib import Path
root = Path.cwd()
work = root / '.tmp-mut-argument/plain-guests'
work.mkdir(exist_ok=True)
compiler = root / '.tmp-mut-argument/plain-candidate/bin/mylang'
result = []
for backend in ('qbe', 'llvm'):
    for name in ('rc_plain_aggregates', 'array_places', 'array_negative_index', 'aggregate_refs', 'rc_aggregate_values', 'dictionary_views'):
        command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'test', f'tests/lang/{name}.my', '--json', '--force', '--rc-runtime=stats']
        if backend == 'llvm':
            command += ['--release']
        run = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, TMPDIR=str(work)))
        row = dict(backend=backend, name=name, command=command, exit=run.returncode, stdout=run.stdout, stderr=run.stderr)
        result.append(row)
        (work / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
        assert run.returncode == 0, row
        print(backend, name, json.loads(run.stdout).get('summary', 'PASS'), flush=True)
