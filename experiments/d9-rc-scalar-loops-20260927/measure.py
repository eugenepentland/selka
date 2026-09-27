from pathlib import Path
import hashlib, importlib.util, json, os, statistics, subprocess

root = Path.cwd()
work = root / '.tmp-pure'
perf_tree = root.parent / 'd9-rc-performance'
spec = importlib.util.spec_from_file_location('acceptance', perf_tree / 'experiments/d9-rc-acceptance-20260926/compare.py')
A = importlib.util.module_from_spec(spec)
spec.loader.exec_module(A)
PC = A.pc
os.environ['TMPDIR'] = str(work / 'tmp')
os.environ['ZIG_LOCAL_CACHE_DIR'] = str(work / 'guest-zig-cache')
program = next(p for p in A.programs() if p['id'] == 'parity/micro/intloop')
baseline_path = A.WORK / 'gc-builds.json'
baseline = json.loads(baseline_path.read_text())
assert baseline['inputs'] == A.inputs()
assert baseline['compiler_sha256'] == A.GC_SHA == A.sha(baseline['compiler'])
compilers = {'before': root.parent / 'd9-rc-integration/.tmp-rc/install-flat-borrow-loops/bin/mylang',
             'after': work / 'install-candidate/bin/mylang'}
data = {'compilers': {side: {'path': str(c), 'sha256': A.sha(c)} for side, c in compilers.items()},
        'source_sha256': A.sha(program['src']), 'program': program, 'cpu': 3,
        'driver_sha256': A.sha(__file__), 'baseline_manifest_sha256': A.sha(baseline_path),
        'builds': [], 'runs': [], 'counts': [], 'summary': {}}

def save():
    A.write(work / 'measurement.json', data)

for backend in ('qbe', 'llvm'):
    binaries = {}
    key = program['build_key'] + '.' + backend
    binaries['gc'] = A.WORK / 'bin/gc' / key
    assert A.sha(binaries['gc']) == baseline['builds'][key]['sha256']
    for side, compiler in compilers.items():
        for counted in (False, True):
            binary = work / f'intloop-{side}-{backend}-{counted}'
            command, cwd = PC.build_command(program, str(compiler), backend, binary, work / ('cache-' + side))
            command = [str(root / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime=stats' if counted else '--rc-runtime']
            build = PC.do_build({'bin': binary, 'cmd': command, 'cwd': cwd})
            data['builds'].append({'side': side, 'backend': backend, 'counted': counted, **build})
            save()
            assert build['ok'], build
            manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
            assert manifest['backend'] == backend
            if counted:
                run = PC.run_spec(program, binary, side)
                done = subprocess.run(['taskset', '-c', '3', *run['argv']], cwd=run['cwd'], env=run['env'], capture_output=True, timeout=60)
                row = {'side': side, 'backend': backend, 'status': done.returncode, 'stdout': done.stdout.decode(),
                       'stderr': done.stderr.decode(), 'binary_sha256': A.sha(binary)}
                data['counts'].append(row)
                assert done.returncode == 0 and done.stdout == Path(program['expected_path']).read_bytes(), row
                count = json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in row['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')))
                row['counts'] = count
                assert not count['saturated'] and count['heap_allocate'] == count['retire']
                assert count['owner_acquire'] + count['heap_allocate'] == count['owner_release']
                assert count['hold_acquire'] == count['hold_release']
                save()
            else:
                binaries[side] = binary
    observed = {side: [] for side in binaries}
    for repeat in range(3):
        for side in (('gc', 'before', 'after') if repeat % 2 == 0 else ('after', 'before', 'gc')):
            binary = binaries[side]
            run = PC.run_spec(program, binary, side)
            stat = work / f'intloop-{backend}-{side}-{repeat}.stat'
            command = ['taskset', '-c', '3', 'perf', 'stat', '--no-scale', '-x,', '-e', 'cpu_core/instructions/u', '-o', str(stat), '--', *run['argv']]
            done = subprocess.run(command, cwd=run['cwd'], env=run['env'], capture_output=True, timeout=60)
            raw = stat.read_text()
            events = [line.split(',') for line in raw.splitlines() if 'instructions' in line and line.split(',')[0].isdigit()]
            assert len(events) == 1 and float(events[0][4]) == 100.0
            instructions = int(events[0][0])
            row = {'side': side, 'backend': backend, 'repeat': repeat, 'command': command, 'status': done.returncode,
                   'stdout': done.stdout.decode(), 'stderr': done.stderr.decode(), 'perf': raw, 'instructions': instructions,
                   'binary_sha256': A.sha(binary), 'environment': {k: v for k, v in run['env'].items() if k.startswith('MYLANG_')}}
            data['runs'].append(row)
            save()
            assert done.returncode == 0 and done.stdout == Path(program['expected_path']).read_bytes(), row
            observed[side].append(instructions)
    medians = {side: statistics.median(samples) for side, samples in observed.items()}
    data['summary'][backend] = {'medians': medians, 'after_before': medians['after'] / medians['before'], 'after_gc': medians['after'] / medians['gc']}
    counts = [row['counts'] for row in data['counts'] if row['backend'] == backend]
    assert len(counts) == 2 and counts[0] == counts[1]
    save()
    print(backend, data['summary'][backend], flush=True)
assert baseline['inputs'] == A.inputs()
assert all(data['compilers'][side]['sha256'] == A.sha(compiler) for side, compiler in compilers.items())
