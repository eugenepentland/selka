#!/usr/bin/env python3
"""Build the schematic guest exactly the way a host application builds it, once
per candidate build policy, so the policies can be timed against each other.

usage: build_policy_arms.py --compiler .tmp/install/bin/mylang --tree <worktree> --work .tmp/audit/arms --arms spec.json

spec.json: {"name": {"build": ["--backend", "llvm", "--llvm-opt", "3", "--lto"]}}
Each arm is `mylang build <tree>/src/schematic/guest/main.my --project --provider
<tree>/src/schematic/native_schematic.c --zig ZIG --cache-dir <work>/cache-<name>
-o <work>/<name>` plus the arm's own build arguments — the same vector
`src/host_native.zig` composes, without the private transport directory.
Writes <work>/<name>, <work>/<name>-build.stderr and <work>/policy-builds.json
(argv, cold and warm build seconds, binary hash).
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, time
from pathlib import Path

ZIG = os.environ.get('MYLANG_ZIG', '/home/epentland/.local/bin/zig')


def environment():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key == 'LD_PRELOAD':
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = '2147483648'
    return env


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', required=True); ap.add_argument('--tree', required=True)
    ap.add_argument('--work', required=True); ap.add_argument('--arms', required=True)
    ap.add_argument('--warm', type=int, default=1, help='extra rebuilds timed against the warm object cache')
    a = ap.parse_args()
    compiler, tree, work = Path(a.compiler).resolve(), Path(a.tree).resolve(), Path(a.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    records = json.loads((work / 'policy-builds.json').read_text()) if (work / 'policy-builds.json').exists() else {}
    for name, arm in json.loads(Path(a.arms).read_text()).items():
        cache = work / f'cache-{name}'
        if cache.exists() and arm.get('cold', True):
            shutil.rmtree(cache)
        output = work / name
        argv = [str(compiler), 'build', str(tree / 'src/schematic/guest/main.my'), '--project',
                '--provider', str(tree / 'src/schematic/native_schematic.c'), '--zig', ZIG,
                '--cache-dir', str(cache), '-o', str(output), *arm.get('build', [])]
        elapsed = []
        for round_number in range(1 + a.warm):
            if output.exists():
                output.unlink()
            started = time.perf_counter()
            result = subprocess.run(argv, cwd=str(tree), env=environment(), capture_output=True, timeout=1800)
            elapsed.append(time.perf_counter() - started)
            if result.returncode != 0:
                sys.stderr.write(result.stderr.decode()[-4000:])
                raise SystemExit(f'failed: {" ".join(argv)}')
            (work / f'{name}-build.stderr').write_bytes(result.stderr)
        records[name] = {'spec': arm, 'build_argv': argv, 'cold_seconds': elapsed[0],
                         'warm_seconds': elapsed[1:], 'binary_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                         'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest()}
        print(f'built {name} cold {elapsed[0]:.2f}s warm {["%.2f" % v for v in elapsed[1:]]}', flush=True)
        (work / 'policy-builds.json').write_text(json.dumps(records, indent=1) + '\n')


if __name__ == '__main__':
    main()
