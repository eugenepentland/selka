from pathlib import Path
import hashlib, json, os, subprocess, time, gzip

root = Path.cwd()
work = root / '.tmp-mut-argument/field-list-read'
guest = root / '.tmp-mut-argument/lox-post-record/current/guest'
cache = root / '.tmp-mut-argument/lox-post-record/current/cache'
compiler = root.parent / 'd9-rc-integration/.tmp-rc/install-loops-fixed/bin/mylang'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(compiler) == '49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5'
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env.update(TMPDIR=str(root.parent / '.d9-rc-mut-argument-tmp'), ZIG_LOCAL_CACHE_DIR=str(root.parent / '.d9-rc-mut-argument-zig-cache'), MYLANG_MEMORY_LIMIT='8G')
result = {'source': '49c6ca07bbba8b35cda4436b831327ac40c8fc87', 'compiler': str(compiler), 'compiler_sha256': sha(compiler), 'sources': {str(p.relative_to(guest)): sha(p) for p in guest.rglob('*.my')}, 'builds': []}
def save():
    (work / 'builds.json').write_text(json.dumps(result, indent=2) + '\n')
for backend in ('qbe', 'llvm'):
    for counted in (False, True):
        binary = work / (backend + ('-stats' if counted else '-production'))
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
cmd = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'emit-project-qbe', 'main.my', '--rc-runtime', '--drop-step-checks', '--drop-frame-checks', '--drop-debug']
p = subprocess.run(cmd, env=env, cwd=guest, capture_output=True, timeout=900)
result['emission'] = {'command': cmd, 'cwd': str(guest), 'exit': p.returncode, 'stderr': p.stderr.decode(), 'sha256': hashlib.sha256(p.stdout).hexdigest()}
save(); assert p.returncode == 0, result['emission']
(work / 'emitted.json.gz').write_bytes(gzip.compress(p.stdout, mtime=0))
print('EMITTED', len(p.stdout), flush=True)
