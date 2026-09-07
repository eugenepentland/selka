"""Actual raw guest I/O and reload checks for the installed application bridge."""
import argparse
import json
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
        measured = run('fn main()->i64{discard io::put(65u8);return 0;}', flags=('--memory-report',))
        assert measured.returncode == 0 and measured.stdout == b'A', measured.stderr
        accounting = json.loads(measured.stderr)
        assert accounting['version'] == 'runtime-memory-v1'
        assert accounting['total']['live'] == 0
        assert accounting['vm_categories']['guest_backing']['live'] == 0
        assert accounting['vm_categories']['bookkeeping_and_snapshots']['peak'] > 0
        assert accounting['logical_slots']['buffers']['total_capacity'] == 0
        assert accounting['vm']['peak'] > 0 and accounting['host']['peak'] > 0
        backed = run('buffer B:i64;result R{ok:B,err:i64}fn main(a:allocator)->i64{arena a as child{match acquire_buffer<R>(child,8){R.ok(b)=>{discard b;},R.err(e)=>{return e;}}}return 0;}', flags=('--memory-report',))
        assert backed.returncode == 0, backed.stderr
        backing_report = json.loads(backed.stderr)
        assert backing_report['vm_categories']['guest_backing']['peak'] > 0
        assert backing_report['vm_categories']['guest_backing']['live'] == 0
        assert backing_report['logical_slots']['buffers']['peak_capacity'] == 8
        assert backing_report['logical_slots']['buffers']['total_capacity'] == 0
        for flag in ('--max-runtime-bytes=0', '--max-vm-bytes=0', '--max-host-bytes=0'):
            exhausted = run('fn main()->i64{discard io::put(65u8);return 0;}', flags=(flag, '--memory-report'))
            assert exhausted.returncode != 0 and not exhausted.stdout, exhausted
            report = next(json.loads(line) for line in exhausted.stderr.splitlines() if line.startswith(b'{'))
            assert report['total']['live'] == 0, report
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
    scoped_checks(runner)
    print('byte I/O: scalar/bulk binary bytes, short writes, ABI validation, configurable budgets and unpublished failures pass')


def scoped_checks(runner):
    import socket
    with tempfile.TemporaryDirectory(prefix='scoped-provider-cli-') as temporary:
        root = Path(temporary)
        data = root / 'data'
        data.mkdir()
        (data / 'existing').write_bytes(b'original')
        outside = root / 'outside'
        outside.write_bytes(b'outside')
        (data / 'link').symlink_to(outside)
        (root / 'io.my').write_text('module io;export length;export byte;export put;host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);host fn put(value:u8)->i64 effects(host);')
        declarations = ('module main;import io;resource File:filesystem;result Open{ok:File,err:i64}'
                        'result Written{ok:u64,err:i64}')
        def run(request, flags, expected=0):
            source = declarations + ('fn main(fs:filesystem_cap)->i64{match acquire_resource<Open>(fs,"' + request + '") {'
                     'Open.err(e)=>{if e==2{return 0;}return 9;},Open.ok(input)=>{let mut file=input;'
                     'acknowledge write_resource<Written>(file,"changed");return ' + str(expected) + ';}}}')
            (root / 'main.my').write_text(source)
            return subprocess.run([str(runner), '--project', str(root), *flags], input=b'', capture_output=True, timeout=15)
        grant = '--allow-dir=' + str(data)
        unavailable = run('r:existing', [])
        assert unavailable.returncode != 0 and b'CapabilityUnavailable' in unavailable.stderr, unavailable
        for request in ['t:existing', 'c:created', 'w:../outside']:
            result = run(request, [grant], 10)
            assert result.returncode == 0, result.stderr
        assert (data / 'existing').read_bytes() == b'original'
        assert not (data / 'created').exists()
        denied = run('t:link', [grant, '--allow-write'], 10)
        assert denied.returncode == 0 and outside.read_bytes() == b'outside', denied.stderr
        created = run('c:created', [grant, '--allow-write'])
        assert created.returncode == 0 and (data / 'created').read_bytes() == b'changed', created.stderr
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()
            server.settimeout(5)
            endpoint = '127.0.0.1:' + str(server.getsockname()[1])
            (root / 'main.my').write_text('module main;import io;resource Socket:network;result Open{ok:Socket,err:i64}'
                'result Written{ok:u64,err:i64}fn main(net:network_cap)->i64{match acquire_resource<Open>(net,"' + endpoint + '") {'
                'Open.err(discard)=>{return 1;},Open.ok(input)=>{let mut socket=input;acknowledge write_resource<Written>(socket,"ping");return 0;}}}')
            result = subprocess.run([str(runner), '--project', str(root), '--allow-endpoint=' + endpoint],
                                    input=b'', capture_output=True, timeout=15)
            assert result.returncode == 0, result.stderr
            peer, _ = server.accept()
            with peer:
                peer.settimeout(5)
                assert peer.recv(4) == b'ping'
                assert peer.recv(1) == b''
    print('scoped providers: CLI grants, read-only create/truncate denial, traversal, symlinks, files and TCP cleanup pass')


if __name__ == '__main__':
    main()
