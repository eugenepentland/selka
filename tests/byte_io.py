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
        def run(source, data=b'', flags=()):
            (root / 'main.my').write_text('module main;import io;' + source)
            return subprocess.run([str(runner), '--project', str(root), *flags], input=data,
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
        (root / 'io.my').write_text(
            'module io;export length;export byte;export put;export Block;export read_block;export write_block;'
            'struct Block{bytes:[256]u8,count:i64}'
            'host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);'
            'host fn put(value:u8)->i64 effects(host);host fn read_block(offset:i64)->Block effects(host);'
            'host fn write_block(block:Block)->i64 effects(host);')
        bulk = ('fn main()->i64{let size=io::length();let mut offset=0;while offset<size{'
                'let block=io::read_block(offset);let count=block.count;'
                'if io::write_block(block)!=count{return 1;}offset+=count;}return 0;}')
        payload = bytes(range(256)) * 16 + b'\x00\xffend'
        copied = run(bulk, payload, ['--max-calls=35', '--max-input=4101', '--max-output=4101'])
        assert copied.returncode == 0 and copied.stdout == payload, copied
        for flags in (['--max-output=257'], ['--max-input=4100'], ['--max-calls=34'],
                      ['--max-work=1'], ['--max-steps=1']):
            failed = run(bulk, payload, flags)
            assert failed.returncode != 0 and failed.stdout == b'', (flags, failed)
        empty = run(bulk, b'', ['--max-input=0', '--max-output=0'])
        assert empty.returncode == 0 and empty.stdout == b'', empty
        # A guest may explicitly accept a short write and publish its prefix.
        short = run('fn main()->i64{let block=io::read_block(0);if io::write_block(block)==3{return 0;}return 1;}',
                    payload, ['--max-output=3'])
        assert short.returncode == 0 and short.stdout == payload[:3], short
        io = root / 'io.my'
        io.write_text(io.read_text().replace('[256]u8', '[255]u8'))
        malformed = run('fn main()->i64{return 0;}')
        assert malformed.returncode != 0 and not malformed.stdout and b'HostSignatureMismatch' in malformed.stderr, malformed
    print('byte I/O: scalar/bulk binary bytes, short writes, ABI validation, configurable budgets and unpublished failures pass')


if __name__ == '__main__':
    main()
