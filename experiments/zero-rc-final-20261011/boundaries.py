#!/usr/bin/env python3
"""Check resource ownership diagnostics through the packaged compiler."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
from measure import digest, save

CASES = {
    'escaped-capability': ('E_SINGLE_OWNER_BORROW', 'func escape(fs: Filesystem) -> Filesystem:\n    with fs.dir("logs") as child:\n        return child\nfunc main() -> int:\n    return 0\n'),
    'moved-parent': ('E_SINGLE_OWNER_OVERLAP', 'func escape(fs: Filesystem) -> Filesystem:\n    with fs.dir("logs") as child:\n        _ = child.exists("a")\n        return fs\nfunc main() -> int:\n    return 0\n'),
    'unscoped-dependency': ('E_ZERO_RC_UNSUPPORTED', 'func escape(fs: Filesystem) -> Filesystem:\n    return fs.dir("logs")\nfunc main() -> int:\n    return 0\n'),
    'foreign-managed-input': ('E_EXTERN_SIGNATURE', 'extern func save(host: Host, value: str) -> int effects(host)\nfunc main() -> int:\n    return 0\n'),
    'foreign-managed-result': ('E_EXTERN_SIGNATURE', 'extern func load(host: Host) -> str effects(host)\nfunc main() -> int:\n    return 0\n'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'zig', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
    result = {'compiler_sha256': digest(args.compiler), 'harness_sha256': digest(__file__), 'refusals': {}}
    for name, (code, source) in CASES.items():
        path = args.output / (name + '.my')
        path.write_text(source)
        ran = subprocess.run([str(args.compiler), 'build', str(path), '--experimental-zero-rc',
                              '--cache-dir', str(args.output / 'cache'), '-o', str(args.output / name)],
                             cwd=ROOT, env=env, capture_output=True, timeout=120)
        stderr = ran.stderr.decode()
        assert ran.returncode != 0 and f'error[{code}]' in stderr, (name, ran.returncode, stderr)
        assert not (args.output / name).exists()
        result['refusals'][name] = {'status': ran.returncode, 'stderr': stderr, 'source_sha256': digest(path)}
    assert digest(args.compiler) == result['compiler_sha256']
    save(HERE / 'boundaries.json', result)
    print(f"{len(result['refusals'])} resource lifetime refusals passed")


if __name__ == '__main__':
    main()
