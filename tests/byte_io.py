"""Actual raw guest I/O and reload checks for the installed application bridge."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


# Two one-line programs appear in several checks, so they are named once.
PUT_A = 'def main() -> i64:\n    _ = io.put(65u8)\n    return 0\n'
RETURN_ZERO = 'def main() -> i64:\n    return 0\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', required=True, type=Path)
    runner = parser.parse_args().runner.resolve()
    with tempfile.TemporaryDirectory(prefix='byte-io-test-') as temporary:
        root = Path(temporary)
        (root / 'io.my').write_text('module io\nexport length\nexport byte\nexport put\n\n\n'
            'host def length() -> i64 effects(host)\n\n\n'
            'host def byte(index: i64) -> u8 effects(host)\n\n\n'
            'host def put(value: u8) -> i64 effects(host)\n')
        def run(source, data=b'', flags=()):
            (root / 'main.my').write_text('module main\nimport io\n\n\n' + source)
            return subprocess.run([str(runner), '--project', str(root), *flags], input=data,
                                  capture_output=True, timeout=30)
        copied = run('def main() -> i64:\n    i = 0\n    while i < io.length():\n        _ = io.put(io.byte(i))\n        i += 1\n    return 0\n', b'\x00\xff\xc0\x80{broken}')
        assert copied.returncode == 0, copied.stderr
        assert copied.stdout == b'\x00\xff\xc0\x80{broken}'
        measured = run(PUT_A, flags=('--memory-report',))
        assert measured.returncode == 0 and measured.stdout == b'A', measured.stderr
        accounting = json.loads(measured.stderr)
        assert accounting['version'] == 'runtime-memory-v1'
        assert accounting['total']['live'] == 0
        assert accounting['vm_categories']['guest_backing']['live'] == 0
        assert accounting['vm_categories']['bookkeeping_and_snapshots']['peak'] > 0
        assert accounting['vm']['peak'] > 0 and accounting['host']['peak'] > 0
        backed = run('def main() -> i64:\n    values: List[i64] = []\n    values.push(8)\n    _ = values\n    return 0\n',
                     flags=('--memory-report',))
        assert backed.returncode == 0, backed.stderr
        backing_report = json.loads(backed.stderr)
        # Managed object storage is measured apart from VM bookkeeping.
        assert backing_report['vm_categories']['guest_backing']['peak'] > 0
        assert backing_report['vm_categories']['guest_backing']['live'] == 0
        assert backing_report['vm_categories']['bookkeeping_and_snapshots']['peak'] > 0
        assert backing_report['total']['live'] == 0
        for flag in ('--max-runtime-bytes=0', '--max-vm-bytes=0', '--max-host-bytes=0'):
            exhausted = run(PUT_A, flags=(flag, '--memory-report'))
            assert exhausted.returncode != 0 and not exhausted.stdout, exhausted
            report = next(json.loads(line) for line in exhausted.stderr.splitlines() if line.startswith(b'{'))
            assert report['total']['live'] == 0, report
        # The same binary reads a changed guest source on its next invocation.
        changed = run(PUT_A)
        assert changed.returncode == 0 and changed.stdout == b'A', changed.stderr
        for source in ['def main() -> i64:\n    _ = io.put(65u8)\n    return 1\n',
                       'def main() -> i64:\n    _ = io.put(65u8)\n    _ = io.byte(-1)\n    return 0\n']:
            failed = run(source)
            assert failed.returncode != 0 and failed.stdout == b'', failed
        length = run('def main() -> i64:\n    if io.length() == 2097152:\n        _ = io.put(66u8)\n        return 0\n    return 1\n', b'x' * (2 * 1024 * 1024))
        assert length.returncode == 0 and length.stdout == b'B', length.stderr
        oversized = run(RETURN_ZERO, b'x' * (2 * 1024 * 1024 + 1))
        assert oversized.returncode != 0 and oversized.stdout == b'', oversized
        (root / 'io.my').write_text(
            'module io\nexport length\nexport byte\nexport put\nexport Block\nexport read_block\nexport write_block\n\n\n'
            'class Block:\n    bytes: [256]u8\n    count: i64\n\n\n'
            'host def length() -> i64 effects(host)\n\n\n'
            'host def byte(index: i64) -> u8 effects(host)\n\n\n'
            'host def put(value: u8) -> i64 effects(host)\n\n\n'
            'host def read_block(offset: i64) -> Block effects(host)\n\n\n'
            'host def write_block(block: Block) -> i64 effects(host)\n')
        bulk = ('def main() -> i64:\n    size = io.length()\n    offset = 0\n    while offset < size:\n'
                '        block = io.read_block(offset)\n        count = block.count\n'
                '        if io.write_block(block) != count:\n            return 1\n'
                '        offset += count\n    return 0\n')
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
        short = run('def main() -> i64:\n    block = io.read_block(0)\n    if io.write_block(block) == 3:\n        return 0\n    return 1\n',
                    payload, ['--max-output=3'])
        assert short.returncode == 0 and short.stdout == payload[:3], short
        io = root / 'io.my'
        io.write_text(io.read_text().replace('[256]u8', '[255]u8'))
        malformed = run(RETURN_ZERO)
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
        (root / 'io.my').write_text('module io\nexport length\nexport byte\nexport put\n\n\n'
            'host def length() -> i64 effects(host)\n\n\n'
            'host def byte(index: i64) -> u8 effects(host)\n\n\n'
            'host def put(value: u8) -> i64 effects(host)\n')
        declarations = ('module main\nimport io\n\n\nresource File: filesystem\n\n'
                        'result Open:\n    ok: File,\n    err: i64\n\n\n'
                        'result Written:\n    ok: u64,\n    err: i64\n\n\n')
        def run(request, flags, expected=0):
            source = declarations + ('def main(fs: filesystem_cap) -> i64:\n'
                     '    request: [' + str(len(request)) + ']u8 = b"' + request + '"\n'
                     '    match acquire_resource[Open](fs, request):\n'
                     '        case Open.err(e):\n            if e == 2:\n                return 0\n            return 9\n'
                     '        case Open.ok(input):\n            file = input\n'
                     '            payload: [7]u8 = b"changed"\n'
                     '            _ = write_resource[Written](file, payload)\n'
                     '            return ' + str(expected) + '\n')
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
            (root / 'main.my').write_text('module main\nimport io\n\n\nresource Socket: network\n\n'
                'result Open:\n    ok: Socket,\n    err: i64\n\n\n'
                'result Written:\n    ok: u64,\n    err: i64\n\n\n'
                'def main(net: network_cap) -> i64:\n'
                '    request: [' + str(len(endpoint)) + ']u8 = b"' + endpoint + '"\n'
                '    match acquire_resource[Open](net, request):\n'
                '        case Open.err(_):\n            return 1\n'
                '        case Open.ok(input):\n            socket = input\n'
                '            payload: [4]u8 = b"ping"\n'
                '            _ = write_resource[Written](socket, payload)\n            return 0\n')
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
