"""Isolated fresh-return n12 diagnostic, actual QBE/LLVM O3 full LTO, median three."""
import hashlib, json, os, statistics, subprocess
from pathlib import Path

root = Path.cwd()
work = root / '.tmp-mut-argument/return-run'
work.mkdir(parents=True, exist_ok=True)
original = root / 'experiments/d9-rc-flat-destruction-20260926/binary_trees_n12.my'
source = work / 'binary_trees_n12.my'
source.write_bytes(original.read_bytes())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
compilers = {'before': root / '.tmp-mut-argument/plain-final/bin/mylang',
             'after': root / '.tmp-mut-argument/return-candidate/bin/mylang'}
assert sha(compilers['before']) == '49372ab04bd2c1408398f7be97e8b7ec2abbca0a6d0f9872226f322cb8bea3a1'
result = {'base': 'ecccc02c', 'cpu': 2, 'depth': 12, 'original_sha256': sha(original), 'source_sha256': sha(source),
          'compilers': {arm: {'path': str(p), 'sha256': sha(p)} for arm, p in compilers.items()}, 'builds': [], 'backends': {}}
def save():
    (work / 'measurement.json').write_text(json.dumps(result, indent=2) + '\n')
def run(command):
    return subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, TMPDIR=str(work)))

for backend in ('qbe', 'llvm'):
    binaries = {}
    counts = {}
    outputs = []
    for arm, compiler in compilers.items():
        for mode in ('rc', 'stats'):
            binary = work / f'trees-{backend}-{arm}-{mode}'
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source), '-o', str(binary), '--cache-dir', str(work / 'cache'), '--keep-symbols', '--rc-runtime=stats' if mode == 'stats' else '--rc-runtime']
            if backend == 'llvm':
                command += ['--backend=llvm', '--llvm-opt=3', '--lto']
            build = run(command)
            row = dict(command=command, exit=build.returncode, stdout=build.stdout, stderr=build.stderr)
            result['builds'].append(row)
            save()
            assert build.returncode == 0, row
            manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
            assert manifest['backend'] == backend and manifest['lto'] == (backend == 'llvm')
            if backend == 'llvm':
                assert manifest['optimization'] == '3'
            row.update(sha256=sha(binary), manifest=manifest)
            save()
            print('built', binary.name, flush=True)
            if mode == 'rc':
                binaries[arm] = binary
            else:
                execution = run(['taskset', '-c', '2', str(binary)])
                assert execution.returncode == 0, execution
                counts[arm] = json.loads(execution.stderr.removeprefix('MYLANG_RC_COUNTS '))
                outputs.append(execution.stdout)
    assert len(set(outputs)) == 1 and counts['before'] == counts['after'], (outputs, counts)
    samples = []
    for repetition in range(3):
        for arm in (('before', 'after') if repetition % 2 == 0 else ('after', 'before')):
            command = ['taskset', '-c', '2', 'perf', 'stat', '-x,', '-e', 'instructions:u,cycles:u', '--', str(binaries[arm])]
            execution = run(command)
            assert execution.returncode == 0 and execution.stdout == outputs[0], execution
            counters = {fields[2]: int(fields[0]) for line in execution.stderr.splitlines() if len(fields := line.split(',')) > 2 and fields[0].isdigit()}
            samples.append(dict(arm=arm, command=command, counters=counters, stderr=execution.stderr))
    medians = {arm: statistics.median(row['counters']['cpu_core/instructions/u'] for row in samples if row['arm'] == arm) for arm in binaries}
    result['backends'][backend] = dict(samples=samples, medians=medians, after_over_before=medians['after'] / medians['before'], counts=counts, stdout=outputs[0])
    save()
    print(backend, medians, result['backends'][backend]['after_over_before'], counts, flush=True)
