"""Actual raw guest I/O and reload checks for the installed application bridge."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', required=True, type=Path)
    runner = parser.parse_args().runner.resolve()
    with tempfile.TemporaryDirectory(prefix='byte-io-test-') as temporary:
        root = Path(temporary)
        (root / 'io.my').write_text('module io;export length;export byte;export put;host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);host fn put(value:u8)->i64 effects(host);')
        def run(source, data=b''):
            (root / 'main.my').write_text('module main;import io;' + source)
            return subprocess.run([str(runner), '--project', str(root)], input=data,
                                  capture_output=True, timeout=30)
        copied = run('fn main()->i64{let mut i=0;while i<io::length(){discard io::put(io::byte(i));i+=1;}return 0;}', b'\x00\xff\xc0\x80{broken}')
        assert copied.returncode == 0, copied.stderr
        assert copied.stdout == b'\x00\xff\xc0\x80{broken}'
        # The same binary reads a changed guest source on its next invocation.
        changed = run('fn main()->i64{discard io::put(65u8);return 0;}')
        assert changed.returncode == 0 and changed.stdout == b'A', changed.stderr
        for source in ['fn main()->i64{discard io::put(65u8);return 1;}',
                       'fn main()->i64{discard io::put(65u8);discard io::byte(-1);return 0;}']:
            failed = run(source)
            assert failed.returncode != 0 and failed.stdout == b'', failed
        length = run('fn main()->i64{if io::length()==2097152{discard io::put(66u8);return 0;}return 1;}', b'x' * (2 * 1024 * 1024))
        assert length.returncode == 0 and length.stdout == b'B', length.stderr
        oversized = run('fn main()->i64{return 0;}', b'x' * (2 * 1024 * 1024 + 1))
        assert oversized.returncode != 0 and oversized.stdout == b'', oversized
    print('byte I/O: raw bytes, reload, unpublished failures, exact input bound pass')


if __name__ == '__main__':
    main()
