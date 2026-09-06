#!/usr/bin/env python3
"""Check transactional native publication and honest build timing reports."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = Path(args.compiler).resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-native-builder-') as directory:
        directory = Path(directory)
        source, executable = directory / 'source.my', directory / 'program'
        source.write_text('fn main()->i64{return 17;}')
        command = [sys.executable, str(root / 'scripts/native.py'), str(source), '-o', str(executable), '--compiler', str(compiler), '--zig', args.zig, '--report']

        def build(extra=(), code=0):
            result = subprocess.run(command + list(extra), capture_output=True, timeout=210, cwd=directory)
            assert result.returncode == code, result.stderr
            if code:
                assert not result.stdout
                return None
            report = json.loads(result.stdout)
            assert report['version'] == 'native-build-v1'
            assert report['generated_c_bytes'] > 0 and len(report['generated_c_sha256']) == 64
            assert report['frontend_seconds'] >= 0 and report['native_seconds'] >= 0
            assert report['driver_reused_compilation'] is False
            return report

        for mode in ('Debug', 'ReleaseFast'):
            first = build(['--mode', mode])
            assert subprocess.check_output([executable]) == b'17\n'
            before = executable.stat()
            second = build(['--mode', mode])
            assert second['generated_c_sha256'] == first['generated_c_sha256']
            assert not second['output_changed'], second
            assert (executable.stat().st_ino, executable.stat().st_mtime_ns) == (before.st_ino, before.st_mtime_ns)
        original = executable.read_bytes()
        before = executable.stat()
        adapter = directory / 'broken.c'
        adapter.write_text('this is invalid C;')
        build(['--provider', str(adapter)], 2)
        adapter.write_text('#include "native_providers.h"\nMylangNativeProviders mylang_native_providers(void) { extern int missing_link_symbol(void); missing_link_symbol(); return (MylangNativeProviders){0}; }')
        build(['--provider', str(adapter)], 2)
        fake = directory / 'partial-zig'
        version = (root / '.zigversion').read_text().strip()
        fake.write_text('#!' + sys.executable + '\nimport pathlib,sys\n'
                        + 'if sys.argv[1] == "version": print(' + repr(version) + '); sys.exit(0)\n'
                        + 'pathlib.Path(sys.argv[sys.argv.index("-o")+1]).write_bytes(b"partial output")\n'
                        + 'sys.exit(0 if "-c" in sys.argv else 1)\n')
        fake.chmod(0o700)
        build(['--zig', str(fake)], 2)
        assert executable.read_bytes() == original
        assert (executable.stat().st_ino, executable.stat().st_mtime_ns) == (before.st_ino, before.st_mtime_ns)
        assert not list(directory.glob('.mylang-native-*'))
        (directory / 'asset.bin').write_bytes(b'17')
        adapter.write_text('#include "native_providers.h"\n'
                           '__asm__(".section .rodata\\nfixture_bytes: .incbin \\"asset.bin\\"\\n.text");\n'
                           'MylangNativeProviders mylang_native_providers(void) { extern const unsigned char fixture_bytes[]; if(fixture_bytes[0] != 49) __builtin_trap(); return (MylangNativeProviders){0}; }')
        build(['--provider', str(adapter)])
        assert not build(['--provider', str(adapter)])['output_changed']
        assert subprocess.check_output([executable]) == b'17\n'
        # Provider-side data remains freshly compiled, without claiming a dependency cache.
        (directory / 'asset.bin').write_bytes(b'27')
        assert build(['--provider', str(adapter)])['output_changed']
        trapped = subprocess.run([executable], capture_output=True)
        assert trapped.returncode != 0
        executable.chmod(0o600)
        assert build(['--mode', 'ReleaseFast'])['output_changed']
        assert os.access(executable, os.X_OK)
        source.write_text('fn main()->i64{return 23;}')
        assert build()['output_changed']
        assert subprocess.check_output([executable]) == b'23\n'
        source.write_text('fn main()->i64{return true;}')
        before = executable.read_bytes()
        build(code=1)
        assert executable.read_bytes() == before
    print('native builder: atomic failure preservation, unchanged output identity, mode reports, executable repair, and changed publication passed')


if __name__ == '__main__':
    main()
