import hashlib
import json
import os
from pathlib import Path
import subprocess

os.sched_setaffinity(0, set(os.sched_getaffinity(0)) - {2, 3, 10, 11})
compiler = Path('.tmp/b3-admission-checkpoint/bin/mylang').resolve()
digest = hashlib.sha256(compiler.read_bytes()).hexdigest()
source = Path('.tmp/b3-admission-checkpoint/source.txt').read_text().strip()
receipt = {'source_commit': source, 'compiler_sha256': digest,
           'purpose': 'Narrow combined list image and malformed-archive admission checkpoint; final full source gate and corpus pending.',
           'modes': {}}
for mode in ('rc', 'gc', 'stats', 'sites'):
    prefix = Path(f'.tmp/list-image-module-admission-{mode}')
    command = ['python3', 'tests/module_compile_oracle.py', str(compiler),
               '.tmp/list-image-project/main.my', '--runtime', mode,
               '--jobs', '1', '--json', str(prefix) + '.json',
               '--work', str(prefix), '--keep']
    result = subprocess.run(command, capture_output=True)
    Path(str(prefix) + '.log').write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, (mode, result.stderr[-2000:], result.stdout[-2000:])
    report = json.loads(Path(str(prefix) + '.json').read_text())
    totals = report['totals']
    assert totals['programs'] == totals['equal'] == totals['executables_identical'] == 1
    assert totals['modules'] == totals['interfaces_compared'] == 2
    assert totals['units_compared'] == totals['units_whole'] == 12
    assert not totals['reference_failed'] and not totals['different']
    assert len(report['results']) == 1
    assert report['results'][0]['exit_status'] == 0
    executions = []
    for kind in ('whole', 'modules'):
        executable = prefix / '0000-main' / kind / 'program'
        run = subprocess.run([str(executable.resolve())], capture_output=True, timeout=30)
        assert run.returncode == 0 and run.stdout == b'list-image-ok\n', (mode, kind, run)
        executions.append({'kind': kind, 'binary_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
                           'exit_status': run.returncode, 'stdout': run.stdout.decode(),
                           'stderr_sha256': hashlib.sha256(run.stderr).hexdigest()})
    assert executions[0]['binary_sha256'] == executions[1]['binary_sha256']
    receipt['modes'][mode] = {'totals': totals, 'executions': executions}
    Path('.tmp/list-image-module-admission-summary.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(mode, totals, flush=True)
assert hashlib.sha256(compiler.read_bytes()).hexdigest() == digest
