"""Native copied host ABI versus VM byte I/O, including preflight and call failures."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time


def invoke(args, **kwargs):
    return subprocess.run([str(a) for a in args], capture_output=True, timeout=90, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='native-host-', dir=root / '.zig-cache') as temporary:
        project = Path(temporary)
        (project / 'io.my').write_text('module io;export length;export byte;export put;'
            'host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);'
            'host fn put(value:u8)->i64 effects(host);')
        entry = project / 'main.my'
        entry.write_text('module main;import io;fn main()->i64{let size=io::length();let mut i=0;'
                         'while i<size{discard io::put(io::byte(i));i+=1;}return 0;}')
        vm = invoke([args.runner.resolve(), '--project', project], input=b'\x00\xffA')
        assert vm.returncode == 0 and vm.stdout == b'\x00\xffA', vm
        for optimize in ['Debug', 'ReleaseFast']:
            executable = project / optimize
            built = invoke(['python3', root / 'scripts/native.py', entry, '--project', '--compiler', args.compiler.resolve(),
                '--zig', args.zig, '--provider', root / 'tests/native_host_provider.c', '--mode', optimize, '-o', executable])
            assert built.returncode == 0, built.stderr
            native = invoke([executable])
            assert native.returncode == 0 and native.stdout == b'0\n' and native.stderr == vm.stdout, native
            for mode, expected in [(1, b'HostMissingRegistration'), (2, b'HostCapabilityDenied'),
                                   (3, b'HostSignatureMismatch'), (4, b'R_HOST_CONTRACT'),
                                   (5, b'R_HOST_FAILURE'), (6, b'R_HOST_LIMIT'),
                                   (7, b'R_HOST_LIMIT'), (8, b'R_HOST_LIMIT')]:
                failed = invoke([executable], env=dict(os.environ, MYLANG_HOST_MODE=str(mode)))
                assert failed.returncode != 0 and not failed.stdout and expected in failed.stderr, (mode, failed)
                assert b'\x00' not in failed.stderr, (mode, failed.stderr)
            vm_limited = invoke([args.runner.resolve(), '--project', project, '--max-calls=1'], input=b'\x00\xffA')
            assert vm_limited.returncode != 0 and b'R_HOST_LIMIT' in vm_limited.stderr, vm_limited
            composite = project / ('composite-' + optimize)
            built = invoke(['python3', root / 'scripts/native.py', root / 'src/native_fixtures/composite.my',
                '--compiler', args.compiler.resolve(), '--zig', args.zig, '--provider', root / 'tests/native_host_composite.c',
                '--mode', optimize, '-o', composite])
            assert built.returncode == 0, built.stderr
            copied = invoke([composite])
            assert copied.returncode == 0 and copied.stdout == b'42\n', copied
            malformed = invoke([composite], env=dict(os.environ, MYLANG_HOST_BAD='1'))
            assert malformed.returncode != 0 and b'R_HOST_CONTRACT' in malformed.stderr, malformed
            started = time.monotonic()
            for _ in range(5):
                assert invoke([executable]).returncode == 0
            print(f'native host {optimize}: five process invocations {time.monotonic() - started:.6f}s (includes startup)')
    print('native host: VM parity, copied bytes, preflight signatures/grants and call/work/value/failure boundaries pass')


if __name__ == '__main__':
    main()
