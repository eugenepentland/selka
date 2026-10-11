#!/usr/bin/env python3
"""CLI refusal boundaries and located invalid-index traps for Stage 2."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    a = parser.parse_args()
    for name in ('compiler', 'zig', 'output'):
        setattr(a, name, getattr(a, name).resolve())
    a.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MYLANG_ZIG=str(a.zig), ZIG=str(a.zig))
    base = 'func main() -> int:\n    const text = "abc"\n    const part = text.borrow(0, 3)\n'
    sources = {
        'default-mode': (base + '    return len(part)\n', []),
        'unsupported-method': (base + '    const changed = part.upper()\n    return len(changed)\n', ['--experimental-zero-rc']),
        'implicit-conversion': (base + '    const saved = str(part)\n    return len(saved)\n', ['--experimental-zero-rc']),
        'aggregate-storage': (base + '    const views = [part]\n    return len(views)\n', ['--experimental-zero-rc']),
        'binary-operation': (base + '    return int(part == part)\n', ['--experimental-zero-rc']),
    }
    result = {'compiler_sha256': digest(a.compiler), 'harness_sha256': digest(__file__), 'refusals': {}, 'traps': {}}
    for name, (source, flags) in sources.items():
        path = a.output / (name + '.my')
        path.write_text(source)
        ran = subprocess.run([str(a.compiler), 'build', str(path), *flags, '--cache-dir', str(a.output / 'cache'),
                              '-o', str(a.output / name)], cwd=ROOT, env=env, capture_output=True, timeout=120)
        stderr = ran.stderr.decode()
        assert ran.returncode != 0 and 'error[' in stderr and 'internal error' not in stderr, (name, ran.returncode, stderr)
        result['refusals'][name] = {'status': ran.returncode, 'stderr': stderr, 'source_sha256': digest(path)}
    for kind, source in {
        'text': '    const data = "aλ🙂"\n',
        'bytes': '    const data = bytes(byte_buffer([0, 128, 255]))\n',
    }.items():
        for index in (-99, 3):
            name = f'{kind}-{index}'
            path, binary = a.output / (name + '.my'), a.output / name
            path.write_text('func main() -> int:\n' + source + '    const part = data.borrow(0, 3)\n' +
                            f'    const item = part[{index}]\n' + ('    return len(item)\n' if kind == 'text' else '    return item\n'))
            for flags in (['--unoptimized'], ['--release', '--verify-facts']):
                build = subprocess.run([str(a.compiler), 'build', str(path), '--experimental-zero-rc', *flags,
                                        '--cache-dir', str(a.output / 'cache'), '-o', str(binary)], cwd=ROOT, env=env, capture_output=True, timeout=120)
                assert build.returncode == 0, build.stderr
                ran = subprocess.run([str(binary)], env=env, capture_output=True, timeout=30)
                stderr = ran.stderr.decode()
                assert ran.returncode != 0 and 'error[R_TEXT_BOUNDS]' in stderr, (name, ran.returncode, stderr)
                result['traps'][name + '/' + flags[0]] = {'status': ran.returncode, 'stderr': stderr, 'binary_sha256': digest(binary)}
    assert digest(a.compiler) == result['compiler_sha256']
    save(HERE / 'boundaries.json', result)
    print(f"{len(result['refusals'])} compiler refusals and {len(result['traps'])} bounds traps passed")


if __name__ == '__main__':
    main()
