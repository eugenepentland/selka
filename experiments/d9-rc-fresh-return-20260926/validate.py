"""Compare ordinary returns, inherited arenas and all relevant admission traps."""
import hashlib, json, os, subprocess
from pathlib import Path

root = Path.cwd()
work = root / '.tmp-mut-argument/return-validation'
work.mkdir(parents=True, exist_ok=True)
compilers = {'before': root / '.tmp-mut-argument/plain-final/bin/mylang',
             'after': root / '.tmp-mut-argument/return-candidate/bin/mylang'}
result = {'compilers': {arm: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for arm, path in compilers.items()}, 'runs': []}
def record(command, backend, arm, mode, expected, trap=None):
    run = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, TMPDIR=str(work)))
    counts = [json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    row = dict(command=command, backend=backend, arm=arm, mode=mode, exit=run.returncode, stdout=run.stdout, stderr=run.stderr, counts=counts)
    result['runs'].append(row)
    (work / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    assert run.returncode == expected, row
    if trap:
        assert trap in run.stderr, row
    for c in counts:
        assert not c['saturated'] and c['heap_allocate'] == c['retire'] and c['heap_allocate'] + c['owner_acquire'] == c['owner_release'] and c['hold_acquire'] == c['hold_release'], row
    print(backend, arm, mode, run.returncode, counts, flush=True)

for backend in ('qbe', 'llvm'):
    for arm, compiler in compilers.items():
        for name in ('rc_fresh_constructors', 'rc_fresh_returns'):
            for mode in ('gc', 'rc'):
                command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'run', f'tests/lang/{name}.my', '--cache-dir=' + str(work / 'cache')]
                command += ([] if backend == 'qbe' else ['--release']) + (['--rc-runtime=stats'] if mode == 'rc' else ['--gc-stress'])
                record(command, backend, arm, name + '-' + mode, 0)
        for probe, option, trap in [('budget', '--max-memory=256K', 'R_MEMORY_BUDGET'), ('frames', '--max-frames=4', 'R_FRAME_LIMIT'), ('steps', '--max-steps=400', 'R_STEP_LIMIT'), ('arithmetic', None, 'R_DIVISION_BY_ZERO'), ('stack-floor', None, 'R_FRAME_LIMIT')]:
            source = 'experiments/d9-rc-fresh-constructor-20260926/' + ('arithmetic-trap.my' if probe == 'arithmetic' else 'trap.my')
            if probe == 'stack-floor':
                source = 'experiments/d9-rc-fresh-return-20260926/stack-floor.my'
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', source, '--run', '--rc-runtime=stats', '--cache-dir', str(work / 'cache')]
            if option:
                command.append(option)
            if backend == 'llvm':
                command += ['--backend=llvm', '--llvm-opt=3', '--lto']
            record(command, backend, arm, probe, 1, trap)
    for mode in ('rc_fresh_constructors-rc', 'rc_fresh_returns-rc', 'budget', 'frames', 'steps', 'arithmetic', 'stack-floor'):
        rows = [row for row in result['runs'] if row['backend'] == backend and row['mode'] == mode]
        assert rows[0]['counts'] == rows[1]['counts'], rows
        assert rows[0]['stdout'] == rows[1]['stdout'], rows
