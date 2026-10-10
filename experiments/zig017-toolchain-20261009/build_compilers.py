#!/usr/bin/env python3
"""Measure compiler-only builds from one frozen Selka source snapshot."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from build_hashes import HERE, ROOT, TOOLS, WORK

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def prepare():
    source = WORK / 'source'
    if source.exists():
        return source
    source.mkdir(parents=True)
    shutil.copytree(ROOT / 'src', source / 'src')
    from compatibility import apply
    apply(source)
    shutil.copy2(ROOT / 'build_identity.zig', source / 'build_identity.zig')
    shutil.copy2(HERE / 'compiler_build.zig', source / 'build.zig')
    for name in re.findall(r'\.path = "([^"]+)"', (ROOT / 'src/user_docs.zig').read_text()):
        dest = source / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, dest)
    hashes = {str(p.relative_to(source)): digest(p) for p in sorted(source.rglob('*')) if p.is_file()}
    (HERE / 'source-manifest.json').write_text(json.dumps(hashes, indent=2) + '\n')
    return source

def main():
    source = prepare()
    llvm = '--llvm' in sys.argv
    result = HERE / ('compiler-llvm-builds.json' if llvm else 'compiler-builds.json')
    rows = []
    for label in (['release', 'pinned'] if llvm else ['custom', 'release', 'pinned']):
        for mode in (['ReleaseSafe'] if llvm else ['Debug', 'ReleaseSafe']):
            name = f'{label}-llvm-{mode}' if llvm else f'{label}-{mode}'
            out = WORK / 'compilers' / name
            out.mkdir(parents=True, exist_ok=True)
            for rep in range(1, 2 if llvm else 4):
                cache = WORK / 'compiler-cache' / name
                if cache.exists():
                    shutil.rmtree(cache)
                for state in ['clean', 'unchanged']:
                    prefix = HERE / f'build-{name}-{rep}-{state}'
                    cmd = [str(TOOLS[label]), 'build', '-Doptimize=' + mode,
                           '--cache-dir', str(cache),
                           '--prefix', str(out), '-j2', '--summary', 'all']
                    if llvm:
                        cmd.append('-Dllvm=true')
                    with prefix.with_suffix('.log').open('w') as log:
                        done = subprocess.run(['/usr/bin/time', '-f', '%e %M %U %S', '-o',
                                               str(prefix.with_suffix('.time')), *cmd], cwd=source,
                                              env={**os.environ, 'TMPDIR': str(WORK / 'tmp'),
                                                   'ZIG_GLOBAL_CACHE_DIR': '/home/epentland/ai/canopy/.zig-global-cache'},
                                              stdout=log, stderr=subprocess.STDOUT)
                    data = prefix.with_suffix('.time').read_text().splitlines()[-1].split()
                    row = {'name': name, 'rep': rep, 'state': state, 'command': cmd,
                           'exit': done.returncode, 'wall_s': float(data[0]),
                           'rss_kib': int(data[1]), 'user_s': float(data[2]), 'sys_s': float(data[3])}
                    if done.returncode == 0:
                        row['binary_sha256'] = digest(out / 'bin/mylang')
                        row['binary_size'] = (out / 'bin/mylang').stat().st_size
                    rows.append(row)
                    result.write_text(json.dumps(rows, indent=2) + '\n')
                    print(name, rep, state, row['wall_s'], done.returncode, flush=True)
                    if done.returncode:
                        break
                if done.returncode:
                    break
            if cache.exists():
                shutil.rmtree(cache)

if __name__ == '__main__':
    main()
