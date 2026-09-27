from pathlib import Path
import hashlib, json, os, re, subprocess

root = Path.cwd()
work = root / '.tmp-pure'
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env.update(TMPDIR=str(work / 'tmp'), ZIG_LOCAL_CACHE_DIR=str(work / 'control-zig-cache'), MYLANG_MEMORY_LIMIT='128M')
compilers = {'before': root.parent / 'd9-rc-integration/.tmp-rc/install-flat-borrow-loops/bin/mylang',
             'after': work / 'install-candidate/bin/mylang'}
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
data = {'compilers': {side: {'path': str(c), 'sha256': sha(c)} for side, c in compilers.items()},
        'driver_sha256': sha(__file__), 'runs': []}

def save():
    (work / 'controls.json').write_text(json.dumps(data, indent=2) + '\n')

cases = [('success', root / 'tests/lang/rc_scalar_loops.my', None, None),
         ('overflow', work / 'controls/overflow.my', None, 'R_OVERFLOW'),
         ('steps', work / 'controls/limits.my', '--max-steps=1000', 'R_STEP_LIMIT'),
         ('frames', work / 'controls/limits.my', '--max-frames=1', 'R_FRAME_LIMIT')]
for name, source, option, trap in cases:
    for backend in ('qbe', 'llvm'):
        for mode in ('gc', 'rc'):
            paired = []
            for side, compiler in compilers.items():
                binary = work / f'control-{name}-{backend}-{mode}-{side}'
                command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source), '-o', str(binary),
                           '--cache-dir=' + str(work / ('control-cache-' + side)), '--mode=ReleaseFast', '--backend=' + backend,
                           '--gc-runtime' if mode == 'gc' else '--rc-runtime=stats']
                if backend == 'llvm':
                    command += ['--llvm-opt=3', '--lto']
                if option:
                    command += [option]
                built = subprocess.run(command, env=env, text=True, capture_output=True, timeout=180)
                row = {'case': name, 'backend': backend, 'mode': mode, 'side': side, 'source_sha256': sha(source),
                       'build_command': command, 'build_status': built.returncode, 'build_stdout': built.stdout, 'build_stderr': built.stderr}
                data['runs'].append(row)
                save()
                assert built.returncode == 0, row
                manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
                assert manifest['backend'] == backend
                runtime_env = dict(env)
                runtime_env['MYLANG_OPTIONS'] = ' '.join(x for x in ('--gc-stress' if mode == 'gc' else '', option) if x)
                done = subprocess.run([str(binary)], env=runtime_env, text=True, capture_output=True, timeout=60)
                row.update(status=done.returncode, stdout=done.stdout, stderr=done.stderr, binary_sha256=sha(binary),
                           environment={k: v for k, v in runtime_env.items() if k.startswith('MYLANG_')})
                save()
                if trap is None:
                    assert done.returncode == 0 and done.stdout == '', row
                else:
                    assert done.returncode == 1 and done.stdout == 'before\n' and trap in done.stderr, row
                if mode == 'rc':
                    counts = json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in done.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')))
                    row['counts'] = counts
                    assert not counts['saturated'] and counts['heap_allocate'] == counts['retire'], row
                    assert counts['owner_acquire'] + counts['heap_allocate'] == counts['owner_release'], row
                    assert counts['hold_acquire'] == counts['hold_release'], row
                paired.append(row)
                save()
                print(name, backend, mode, side, 'pass', flush=True)
            assert paired[0].get('counts') == paired[1].get('counts'), paired
            clean = lambda s: re.sub(r'^MYLANG_RC_COUNTS .*\n?', '', s, flags=re.M)
            assert clean(paired[0]['stderr']) == clean(paired[1]['stderr']), paired
assert all(data['compilers'][side]['sha256'] == sha(compiler) for side, compiler in compilers.items())
