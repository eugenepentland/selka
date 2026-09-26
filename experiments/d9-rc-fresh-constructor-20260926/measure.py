"""Build one candidate and compare it with the shared immutable cumulative control."""
import hashlib, json, os, statistics, subprocess
from pathlib import Path
root = Path.cwd()
work = root / '.tmp-mut-argument/fresh-run'
work.mkdir(parents=True, exist_ok=True)
shared = root.parent / 'd9-rc-flat-destruction-astra/.tmp-flat/cumulative-19e'
frozen = root.parent / 'd9-rc-contract-astra/.tmp-rc/profile'
compiler = root / '.tmp-mut-argument/fresh-candidate/bin/mylang'
control = root.parent / 'd9-rc-integration/.tmp-rc/install-history-flat/bin/mylang'
source = shared / 'binary_trees_n12.my'
expected = (root / 'experiments/d9-rc-inert-return-20260926/rc-n12.stdout').read_text()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(control) == '1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe'
result = {'base': '19e16e1d96112e9ccc741fa0c430ea97173a1032', 'source_sha256': sha(source), 'cpu': 2,
          'compilers': {'before': {'path': str(control), 'sha256': sha(control)}, 'after': {'path': str(compiler), 'sha256': sha(compiler)}},
          'builds': [], 'backends': {}}
def save():
    (work / 'measurement.json').write_text(json.dumps(result, indent=2) + '\n')
for backend in ('qbe', 'llvm'):
    for mode in ('rc', 'stats'):
        binary = work / f'{backend}-{mode}-n12'
        command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source), '-o', str(binary),
                   '--cache-dir', str(work / f'cache-{backend}'), '--keep-symbols', '--rc-runtime=stats' if mode == 'stats' else '--rc-runtime']
        if backend == 'llvm':
            command += ['--backend=llvm', '--llvm-opt=3', '--lto']
        run = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, TMPDIR=str(work)))
        result['builds'].append({'command': command, 'exit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr})
        save()
        assert run.returncode == 0, result['builds'][-1]
        manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
        assert manifest['backend'] == backend and manifest['lto'] == (backend == 'llvm')
        if backend == 'llvm':
            assert manifest['optimization'] == '3'
        result['builds'][-1].update(sha256=sha(binary), manifest=manifest)
        save()
        print('built', binary.name, flush=True)
    binaries = {'before': shared / f'{backend}-rc-n12', 'after': work / f'{backend}-rc-n12', 'gc': frozen / f'gap-allocator-{backend}-gc-n12'}
    samples = []
    for iteration in range(3):
        for arm in (('before', 'after', 'gc') if iteration % 2 == 0 else ('gc', 'after', 'before')):
            command = ['taskset', '-c', '2', 'perf', 'stat', '-x,', '-e', 'instructions:u,cycles:u', '--', str(binaries[arm])]
            run = subprocess.run(command, text=True, capture_output=True)
            assert run.returncode == 0 and run.stdout == expected, (command, run.returncode, run.stdout, run.stderr)
            counters = {fields[2]: int(fields[0]) for line in run.stderr.splitlines() if len(fields := line.split(',')) > 2 and fields[0].isdigit()}
            samples.append({'arm': arm, 'command': command, 'counters': counters, 'stderr': run.stderr})
    counts = {}
    for arm, directory in [('before', shared), ('after', work)]:
        command = ['taskset', '-c', '2', str(directory / f'{backend}-stats-n12')]
        run = subprocess.run(command, text=True, capture_output=True)
        assert run.returncode == 0 and run.stdout == expected, run
        counts[arm] = json.loads(run.stderr.removeprefix('MYLANG_RC_COUNTS '))
    assert counts['before'] == counts['after'], counts
    medians = {arm: statistics.median(row['counters']['cpu_core/instructions/u'] for row in samples if row['arm'] == arm) for arm in binaries}
    result['backends'][backend] = {'samples': samples, 'medians': medians, 'after_over_before': medians['after'] / medians['before'],
                                    'after_over_gc': medians['after'] / medians['gc'], 'counts': counts,
                                    'binaries': {arm: {'path': str(path), 'sha256': sha(path)} for arm, path in binaries.items()}}
    save()
    print(backend, medians, result['backends'][backend]['after_over_before'], counts['after'], flush=True)
