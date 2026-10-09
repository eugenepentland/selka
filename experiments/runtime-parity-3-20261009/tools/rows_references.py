#!/usr/bin/env python3
"""Rebuild expanded/run.py's 16 reference executables without its retired QBE arm.

The reference source paths, flags, and Rust text Cargo recipe are unchanged.
Every reference is checked against the expanded registry's three edge probes.
All build scratch stays in this worktree; installed references live in --work.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
import registry


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--receipt', required=True, type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    (work / 'bin').mkdir(parents=True, exist_ok=True)
    scratch = ROOT / '.tmp/rp3/rows-references'
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(scratch), GOMAXPROCS='1', GOTOOLCHAIN='local',
               GOAMD64='v1', GOFLAGS='', GOWORK='off', CGO_ENABLED='0',
               ZIG_LOCAL_CACHE_DIR=str(ROOT / '.zig-cache-rp3-rows'),
               GOCACHE=str(scratch / 'go'), RUSTC=str(Path.home() / '.cargo/bin/rustc'))
    for key in ('RUSTFLAGS', 'CFLAGS', 'CXXFLAGS', 'GOEXPERIMENT'):
        env.pop(key, None)
    receipt = {'method': 'expanded/run.py reference recipes, all reference arms; registry edge probes',
               'builds': {}, 'probes': [], 'complete': False}
    slot = str(ROOT / 'scripts/build-slot.sh')
    for group in registry.GROUPS:
        source = ROOT / 'benchmarks/runtime' / ('ports' if group == 'legacy' else 'expanded/' + group)
        for arm in ('rust', 'zig-safe', 'zig-fast', 'go'):
            binary = work / 'bin' / (group + '-' + arm)
            copy = None
            extension = 'rs' if arm == 'rust' else 'go' if arm == 'go' else 'zig'
            path = source / ('main.' + extension)
            if arm == 'rust' and group == 'text':
                command = [str(Path.home() / '.cargo/bin/cargo'), 'build', '--release', '--locked',
                           '--manifest-path', str(source / 'Cargo.toml'), '--target-dir', str(scratch / 'cargo-target')]
                copy = scratch / 'cargo-target/release/runtime_text'
            elif arm == 'rust':
                command = [env['RUSTC'], '-O', '--edition', '2021', str(path), '-o', str(binary)]
            elif arm == 'go':
                command = ['go', 'build', '-o', str(binary), str(path)]
            else:
                command = ['zig', 'build-exe', str(path), '-lc', '-O',
                           'ReleaseSafe' if arm == 'zig-safe' else 'ReleaseFast', '-femit-bin=' + str(binary)]
            full = [slot, 'build', *command]
            proc = subprocess.run(full, cwd=ROOT, env=env, capture_output=True, text=True)
            name = group + '/' + arm
            receipt['builds'][name] = {'command': full, 'status': proc.returncode,
                                      'source_sha256': digest(path), 'stderr': proc.stderr[-4000:]}
            args.receipt.write_text(json.dumps(receipt, indent=1) + '\n')
            if proc.returncode:
                raise SystemExit(name + ': ' + proc.stderr)
            if copy:
                shutil.copy2(copy, binary)
            receipt['builds'][name]['binary_sha256'] = digest(binary)
            print('built ' + name, flush=True)
    for case, meta in registry.inventory().items():
        for size, seed, count in registry.EDGE_PROBES:
            expected = registry.checksum(case, size, count, seed)
            for arm in ('rust', 'zig-safe', 'zig-fast', 'go'):
                binary = work / 'bin' / (meta['group'] + '-' + arm)
                proc = subprocess.run(['taskset', '-c', '8', str(binary), case, str(size), str(count), str(seed)],
                                      capture_output=True, text=True, timeout=120)
                fields = proc.stdout.split()
                good = proc.returncode == 0 and len(fields) == 2 and fields[0] == str(expected) and fields[1].isdigit()
                receipt['probes'].append({'case': case, 'arm': arm, 'size': size, 'seed': seed,
                                          'iterations': count, 'passed': good})
                if not good:
                    args.receipt.write_text(json.dumps(receipt, indent=1) + '\n')
                    raise SystemExit(f'{case}/{arm}: {proc.returncode}: {proc.stdout!r} {proc.stderr!r}')
    receipt['complete'] = True
    args.receipt.write_text(json.dumps(receipt, indent=1) + '\n')
    print(f"16 reference binaries; {len(receipt['probes'])} edge probes passed", flush=True)


if __name__ == '__main__':
    main()
