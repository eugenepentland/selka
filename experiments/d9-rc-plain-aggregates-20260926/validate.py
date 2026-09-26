"""Compare the immutable before/after compilers on actual native guest paths."""
import hashlib, json, os, subprocess
from pathlib import Path

root = Path.cwd()
work = root / '.tmp-mut-argument/plain-run'
work.mkdir(parents=True, exist_ok=True)
compilers = {'before': root / '.tmp-mut-argument/fresh-final/bin/mylang',
             'after': root / '.tmp-mut-argument/plain-candidate/bin/mylang'}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(compilers['before']) == '1b85b2f80b4b229b7bed0c8a120457df28892501edbd0b4732ebb338cd334f8b'
result = {'compilers': {arm: {'path': str(path), 'sha256': sha(path)} for arm, path in compilers.items()}, 'runs': []}
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
        for mode in ('gc', 'rc'):
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'run', 'tests/lang/rc_plain_aggregates.my', '--cache-dir=' + str(work / 'cache')]
            command += ([] if backend == 'qbe' else ['--release']) + (['--rc-runtime=stats'] if mode == 'rc' else ['--gc-stress'])
            record(command, backend, arm, 'guest-' + mode, 0)
        for probe in ('bounds', 'arithmetic'):
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', f'experiments/d9-rc-plain-aggregates-20260926/{probe}.my', '--run', '--rc-runtime=stats', '--cache-dir', str(work / 'cache')]
            if backend == 'llvm':
                command += ['--backend=llvm', '--llvm-opt=3', '--lto']
            record(command, backend, arm, probe, 1, 'R_LIST_BOUNDS' if probe == 'bounds' else 'R_DIVISION_BY_ZERO')
    for mode in ('guest-rc', 'bounds', 'arithmetic'):
        rows = [row for row in result['runs'] if row['backend'] == backend and row['mode'] == mode]
        assert rows[0]['counts'] == rows[1]['counts'], rows
        assert rows[0]['stdout'] == rows[1]['stdout'], rows
        if mode != 'guest-rc':
            diagnostics = ['\n'.join(line for line in row['stderr'].splitlines() if not line.startswith('build-slot:')) for row in rows]
            assert diagnostics[0] == diagnostics[1], rows
