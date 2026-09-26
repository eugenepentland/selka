import collections, hashlib, json, os, statistics, subprocess
from pathlib import Path

root = Path.cwd()
work = root / '.tmp-flat'
frozen = root.parent / 'd9-rc-contract-astra/.tmp-rc/profile'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
expected = (work / 'expected.stdout').read_text()
prior = json.loads((root / 'experiments/d9-rc-inert-return-20260926/measurement.json').read_text())
compiler = frozen / 'install-inert-return-final/bin/mylang'
assert sha(compiler) == prior['compilers']['after']
result = {'source_commit': 'e8696c1315a5c0b64e1b9c2343c45f84e31b46fd', 'compiler': str(compiler), 'compiler_sha256': sha(compiler), 'cpu': 2, 'backends': {}}
for backend in ('qbe', 'llvm'):
    bins = {'rc': frozen / f'inert-return-final-{backend}-rc-n12', 'gc': frozen / f'gap-allocator-{backend}-gc-n12'}
    stats = frozen / f'inert-return-final-{backend}-stats-n12'
    record = {'binaries': {}, 'samples': []}
    for arm, binary in bins.items():
        assert sha(binary) == prior['backends'][backend]['binary_sha256']['after' if arm == 'rc' else 'gc']
        manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
        assert manifest['backend'] == backend and manifest['lto'] == (backend == 'llvm')
        record['binaries'][arm] = {'path': str(binary), 'sha256': sha(binary), 'manifest': manifest}
    for i in range(5):
        for arm in (('rc', 'gc') if i % 2 == 0 else ('gc', 'rc')):
            command = ['taskset', '-c', '2', 'perf', 'stat', '-x,', '-e', 'instructions:u,cycles:u', '--', str(bins[arm])]
            run = subprocess.run(command, capture_output=True, text=True, check=True)
            assert run.stdout == expected
            counters = {f[2]: int(f[0]) for line in run.stderr.splitlines() if len(f := line.split(',')) > 2 and f[0].isdigit()}
            record['samples'].append({'arm': arm, 'command': command, 'counters': counters, 'stderr': run.stderr, 'stdout_sha256': hashlib.sha256(run.stdout.encode()).hexdigest()})
    counted = subprocess.run(['taskset', '-c', '2', str(stats)], capture_output=True, text=True, check=True)
    assert counted.stdout == expected
    record['counts'] = json.loads(counted.stderr.removeprefix('MYLANG_RC_COUNTS '))
    assert record['counts'] == prior['backends'][backend]['counts']['after']
    record['stats_sha256'] = sha(stats)
    record['medians'] = {arm: statistics.median(s['counters']['cpu_core/instructions/u'] for s in record['samples'] if s['arm'] == arm) for arm in bins}
    record['rc_over_gc'] = record['medians']['rc'] / record['medians']['gc']
    result['backends'][backend] = record
    (work / 'measure.json').write_text(json.dumps(result, indent=2) + '\n')
    print(backend, record['medians'], record['rc_over_gc'], flush=True)

for backend in ('qbe', 'llvm'):
    binary = work / f'inert-{backend}-rc-repeat'
    command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(work / 'binary_trees_n12_repeat.my'), '-o', str(binary), '--cache-dir', str(work / f'cache-{backend}'), '--rc-runtime', '--keep-symbols']
    if backend == 'llvm':
        command += ['--backend=llvm', '--llvm-opt=3', '--lto']
    run = subprocess.run(command, capture_output=True, text=True, env=dict(os.environ, TMPDIR=str(work)), check=True)
    result['backends'][backend]['repeat_build'] = {'command': command, 'stdout': run.stdout, 'stderr': run.stderr, 'sha256': sha(binary)}
    (work / 'measure.json').write_text(json.dumps(result, indent=2) + '\n')
    for arm, target in [('rc', binary), ('gc', frozen / f'gap-allocator-{backend}-gc-repeat')]:
        name = f'{backend}-{arm}'
        data = work / (name + '.data')
        command = ['perf', 'record', '-q', '-e', 'cpu_core/instructions/u', '-F', '199', '-o', str(data), '--', 'taskset', '-c', '2', str(target)]
        run = subprocess.run(command, capture_output=True, text=True, check=True)
        assert run.stdout == expected * 240
        samples = subprocess.check_output(['perf', 'script', '-i', str(data), '-F', 'ip,sym,dso,period'], text=True)
        (work / (name + '.samples.txt')).write_text(samples)
        report = subprocess.check_output(['perf', 'report', '--stdio', '--no-children', '--sort', 'symbol,dso', '--percent-limit', '0.3', '-i', str(data)], text=True)
        (work / (name + '.report.txt')).write_text(report)
        stats = subprocess.run(['perf', 'report', '--stdio', '--stats', '-i', str(data)], capture_output=True, text=True, check=True)
        (work / (name + '.stats.txt')).write_text(stats.stdout + stats.stderr)
        result['backends'][backend][arm + '_profile'] = {'binary': str(target), 'sha256': sha(target), 'command': command, 'stderr': run.stderr, 'sample_lines': len(samples.splitlines()), 'stdout_sha256': hashlib.sha256(run.stdout.encode()).hexdigest()}
        (work / 'measure.json').write_text(json.dumps(result, indent=2) + '\n')
        print(name, len(samples.splitlines()), 'sample lines', flush=True)
