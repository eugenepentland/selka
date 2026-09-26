"""Exercise actual unaccounted construction and refusal/failure controls."""
import hashlib, json, os, subprocess
from pathlib import Path
root = Path.cwd()
work = root / '.tmp-mut-argument/fresh-validation'
work.mkdir(parents=True, exist_ok=True)
compilers = {'before': root.parent / 'd9-rc-integration/.tmp-rc/install-history-flat/bin/mylang',
             'after': root / '.tmp-mut-argument/fresh-candidate/bin/mylang'}
result = {'compilers': {name: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for name, path in compilers.items()}, 'runs': []}
def save():
    (work / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
def record(command, backend, arm, mode, expected, trap=None):
    run = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, TMPDIR=str(work)))
    counts = [json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    row = {'backend': backend, 'arm': arm, 'mode': mode, 'command': command, 'exit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr, 'counts': counts}
    result['runs'].append(row)
    save()
    assert run.returncode == expected, row
    if trap:
        assert trap in run.stderr, row
    if counts:
        c = counts[0]
        assert not c['saturated'] and c['heap_allocate'] == c['retire'] and c['heap_allocate'] + c['owner_acquire'] == c['owner_release'] and c['hold_acquire'] == c['hold_release'], row
    print(backend, arm, mode, run.returncode, counts, flush=True)
for backend in ('qbe', 'llvm'):
    flags = [] if backend == 'qbe' else ['--backend=llvm', '--llvm-opt=3', '--lto']
    for arm, compiler in compilers.items():
        for mode in ('gc', 'rc'):
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'run', 'tests/lang/rc_fresh_constructors.my', '--cache-dir=' + str(work / 'cache')]
            command += ([] if backend == 'qbe' else ['--release']) + (['--rc-runtime=stats'] if mode == 'rc' else ['--gc-stress'])
            record(command, backend, arm, 'guest-' + mode, 0)
        for mode, option, trap in [('budget', '--max-memory=256K', 'R_MEMORY_BUDGET'), ('frames', '--max-frames=4', 'R_FRAME_LIMIT')]:
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', 'experiments/d9-rc-fresh-constructor-20260926/trap.my', '--run', '--rc-runtime=stats', option, '--cache-dir', str(work / 'cache')]
            record(command + flags, backend, arm, mode, 1, trap)
    pairs = result['runs'][-8:]
    for mode in ('guest-rc', 'budget', 'frames'):
        rows = [row for row in pairs if row['mode'] == mode]
        assert rows[0]['counts'] == rows[1]['counts'], rows
