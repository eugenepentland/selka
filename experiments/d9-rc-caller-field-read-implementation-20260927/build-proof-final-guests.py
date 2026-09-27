from pathlib import Path
import hashlib, json, os, subprocess, time, gzip

root = Path.cwd()
work = root / '.tmp-mut-argument/caller-field-read'
guest = root / '.tmp-mut-argument/lox-post-record/current/guest'
cache = root / '.tmp-mut-argument/lox-post-record/current/cache'
compiler = root / '.tmp-mut-argument/caller-field-read/install-proof-final/bin/mylang'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert compiler.exists()
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env.update(TMPDIR=str(root.parent / '.d9-rc-mut-argument-tmp'), ZIG_LOCAL_CACHE_DIR=str(root.parent / '.d9-rc-mut-argument-zig-cache'), MYLANG_MEMORY_LIMIT='8G')
result = {'source': 'fa9e4cd5 plus archived incoming-lifetime diff', 'compiler': str(compiler), 'compiler_sha256': sha(compiler), 'sources': {str(p.relative_to(guest)): sha(p) for p in guest.rglob('*.my')}, 'builds': []}
def save():
    (work / 'proof-final-builds.json').write_text(json.dumps(result, indent=2) + '\n')
for backend in ('qbe', 'llvm'):
    for counted in (False, True):
        binary = work / ('proof-final-' + backend + ('-stats' if counted else '-production'))
        cmd = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', 'main.my', '--project', '-o', str(binary), '--cache-dir', str(cache), '--backend=' + backend, '--keep-symbols', '--rc-runtime=stats' if counted else '--rc-runtime']
        if backend == 'llvm': cmd += ['--llvm-opt=3', '--lto']
        print('START', backend, counted, flush=True)
        start = time.monotonic()
        p = subprocess.run(cmd, env=env, cwd=guest, capture_output=True, text=True, timeout=900)
        row = {'command': cmd, 'cwd': str(guest), 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr, 'backend': backend, 'counted': counted, 'seconds': time.monotonic() - start}
        result['builds'].append(row); save()
        assert p.returncode == 0, row
        row.update(binary=str(binary), binary_sha256=sha(binary), manifest=json.loads(Path(str(binary) + '.qbe-manifest.json').read_text()))
        assert row['manifest']['backend'] == backend
        save(); print('DONE', backend, counted, round(row['seconds'], 2), flush=True)

old=json.loads((work/'candidate-builds.json').read_text())
for row in result['builds']:
 prior=next(x for x in old['builds'] if x['backend']==row['backend'] and x['counted']==row['counted'])
 assert row['binary_sha256']==prior['binary_sha256'],(row['binary'],row['binary_sha256'],prior['binary_sha256'])
print('four full N10 binaries byte-identical to measured originals',flush=True)
