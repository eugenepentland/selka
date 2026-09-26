import hashlib, json, os, subprocess
from pathlib import Path

root = Path.cwd()
work = root / '.tmp-repeat'
compiler = root / 'zig-out/bin/mylang'
result = {
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
    'runs': {},
}
for backend in ('qbe', 'llvm'):
    for mode in ('gc', 'rc'):
        for fixture in ('permanent', 'rc_box_writeback'):
            source = work / (fixture + '.my')
            command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'run', str(source), '--cache-dir=' + str(work / 'joined-cache')]
            command += ['--gc-runtime', '--gc-stress'] if mode == 'gc' else ['--rc-runtime=stats']
            if backend == 'llvm':
                command += ['--release']
            run = subprocess.run(command, capture_output=True, text=True, env=dict(os.environ, TMPDIR=str(work)), timeout=600)
            counts = [json.loads(line.split(' ', 1)[1]) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
            key = f'{backend}/{mode}/{fixture}'
            result['runs'][key] = {'command': command, 'source': source.read_text(), 'exit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr, 'counts': counts}
            (work / 'joined.json').write_text(json.dumps(result, indent=2) + '\n')
            print(key, run.returncode, repr(run.stdout), counts, flush=True)
            assert run.returncode == 0 and 'False' not in run.stdout, result['runs'][key]
            if mode == 'rc':
                assert len(counts) == 1
                c = counts[0]
                assert c['runtime'] == 'rc-v3-counting' and not c['saturated']
                assert c['heap_allocate'] == c['retire']
                assert c['heap_allocate'] + c['owner_acquire'] == c['owner_release']
                assert c['hold_acquire'] == c['hold_release']
            else:
                assert not counts
