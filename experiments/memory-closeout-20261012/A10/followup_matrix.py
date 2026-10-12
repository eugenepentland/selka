#!/usr/bin/env python3
"""Doctest and persistent-check qualification; run under shared admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--scratch', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--default', action='store_true')
a = p.parse_args()
compiler = a.compiler.resolve()
scratch = a.scratch.resolve()
scratch.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parent
cache = str(scratch / 'cache')
rows = []
env = dict(os.environ, MYL_CORE_LEAKCHECK='1')
flags = [] if a.default else ['--experimental-zero-rc']

def run(name, args, expected=0, data=None):
    cmd = [str(compiler), *map(str,args)]
    r = subprocess.run(cmd, input=data, text=True, capture_output=True, env=env)
    row = dict(name=name, argv=cmd, status=r.returncode, expected=expected,
               passed=r.returncode == expected, stdout=r.stdout, stderr=r.stderr)
    rows.append(row)
    return row

for command, source in [('check-module','library.my'), ('check-project','guest_tests.my')]:
    run(command, [command, root/'fixtures'/source, *flags, '--cache-dir', cache, '--diagnostics=json'])
for source, statuses in [('guest_tests.my',[0,0,0,0,0]), ('invalid_move.my',[1,1,0,1,0])]:
    row = run('session-'+source, ['check-session',root/'fixtures'/source,*flags,'--cache-dir',cache,'--diagnostics=json'],
              data='check\ncheck\nclear\ncheck\nquit\n')
    replies = [json.loads(line) for line in row['stdout'].splitlines()]
    row['passed'] = row['passed'] and [x['status'] for x in replies] == statuses
    if source == 'invalid_move.my':
        row['passed'] = row['passed'] and row['stderr'].count('E_SINGLE_OWNER_MOVED') == 3

docs = scratch/'docs-root'
(docs/'docs').mkdir(parents=True, exist_ok=True)
(docs/'README.md').write_text('''```mylang
# doc: expect ready
func main(out: Stream) -> int:
    out.print("ready")
    return 0
```

```mylang
# doc: check
func independent(value: str) -> str:
    return value.copy()
```

```mylang
# doc: expect-error E_SINGLE_OWNER_MOVED
func invalid() -> bool:
    const value = "x-" + str(7)
    const moved = value
    return value == moved
```
''')
for label in ['first','repeat']:
    row = run('doctest-'+label,['doctest',docs,*flags,'--jobs','1','--report',scratch/('doctest-'+label+'.json')])
    row['passed'] = row['passed'] and '1 run, 2 checked' in row['stdout'] and '0 failed' in row['stdout']
result = dict(default=a.default, compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
              results=rows, success=all(x['passed'] for x in rows))
a.output.write_text(json.dumps(result,indent=2)+'\n')
for row in rows: print(row['name'],row['status'],'PASS' if row['passed'] else 'FAIL',flush=True)
raise SystemExit(0 if result['success'] else 1)
