#!/usr/bin/env python3
"""Temporary pre-retirement RC compatibility control; never count-free qualification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(argv, env, cwd):
    result = subprocess.run(list(map(str, argv)), env=env, cwd=cwd,
                            capture_output=True, text=True, timeout=600)
    return {'argv': list(map(str, argv)), 'status': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'source', 'output', 'zig'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    assert digest(args.compiler) == '540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef'
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ)
    for name in ('MYLANG_CORE_SANITIZE', 'MYLANG_OPTIONS', 'MYLANG_COUNTERS'):
        env.pop(name, None)
    binary = args.output/'ordinary-borrow'
    counts = args.output/'counts.json'
    built = run([args.compiler, 'build', args.source, '--release', '--counters', '--zig', args.zig,
                 '--cache-dir', args.output/'cache', '-o', binary], env, args.output)
    result = {'scope': 'temporary ordinary RC compatibility control before retirement; not zero-RC/default qualification',
              'source_revision': 'bed11cf3bf3102ffec44487e431a1573fdf02ad5',
              'compiler_sha256': digest(args.compiler), 'source_sha256': digest(args.source),
              'harness_sha256': digest(__file__), 'build': built, 'passed': False}
    if built['status'] == 0:
        ran = run([binary], dict(env, MYLANG_COUNTERS=str(counts)), args.output)
        result['run'] = ran; result['binary_sha256'] = digest(binary)
        result['passed'] = ran['status'] == 0 and ran['stdout'] == 'ordinary-borrow 2\n' and ran['stderr'] == ''
        if counts.exists():
            result['totals'] = json.loads(counts.read_text())['totals']
            result['passed'] &= result['totals']['live_bytes_at_exit'] == 0
        else:
            result['passed'] = False; result['missing_counts'] = True
    (args.output/'results.json').write_text(json.dumps(result, indent=2)+'\n')
    print('ordinary RC control', 'pass' if result['passed'] else 'FAIL', flush=True)
    raise SystemExit(not result['passed'])


if __name__ == '__main__':
    main()
