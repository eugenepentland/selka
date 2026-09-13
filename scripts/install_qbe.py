#!/usr/bin/env python3
"""Build the checksum-pinned QBE release using the pinned Zig C compiler."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DIGEST = 'd587905d620dc5e1d2bfa7c2cc642b9b837aa89a3188c6e37b53d756cf66e320'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--output', type=Path, default=ROOT / '.mylang-cache/toolchain/qbe')
    args = parser.parse_args()
    version = (ROOT / '.qbeversion').read_text().strip()
    if version != '1.3':
        parser.error('update the release checksum when changing .qbeversion')
    expected = (ROOT / '.zigversion').read_text().strip()
    if subprocess.check_output([args.zig, 'version'], text=True).strip() != expected:
        parser.error(f'requires Zig {expected}')
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.qbe-build-', dir=output.parent) as directory:
        directory = Path(directory)
        archive = directory / 'qbe.tar.xz'
        with urllib.request.urlopen(f'https://c9x.me/compile/release/qbe-{version}.tar.xz', timeout=60) as response:
            archive.write_bytes(response.read())
        if hashlib.sha256(archive.read_bytes()).hexdigest() != DIGEST:
            raise RuntimeError('QBE release checksum mismatch')
        with tarfile.open(archive) as source:
            source.extractall(directory, filter='data')
        source = directory / ('qbe-' + version)
        (source / 'config.h').write_text('#define Deftgt T_amd64_sysv\n')
        inputs = [str(path) for subdir in [source, source / 'amd64', source / 'arm64', source / 'rv64']
                  for path in sorted(subdir.glob('*.c'))]
        candidate = directory / 'qbe'
        subprocess.run([args.zig, 'cc', '-std=c99', '-O2', *inputs, '-o', str(candidate)], check=True, timeout=180)
        candidate.replace(output)
    print(output)


if __name__ == '__main__':
    main()
