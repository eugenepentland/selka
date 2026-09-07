"""Source standard I/O VM-fixture parity, partial progress and native unwind checks."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from native_memory import memory


def invoke(argv, env=None):
    return subprocess.run([str(x) for x in argv], capture_output=True, timeout=90, env=env)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(dir=root / '.mylang-cache/validation/tmp', prefix='stdlib-io-') as tmp:
        directory = Path(tmp)
        count = 0
        allocation_positions = 0
        for fixture in ('read', 'collect', 'write'):
            source = directory / 'main.my'
            source.write_bytes((root / 'src/stdlib/fixtures/io' / (fixture + '.my')).read_bytes())
            emitted = invoke([args.compiler.resolve(), 'emit-project-c', source])
            assert emitted.returncode == 0, emitted.stderr
            cfile = directory / 'guest.c'
            cfile.write_bytes((root / 'tests/native_memory.h').read_bytes() + b'\n' + emitted.stdout)
            binary = directory / 'guest'
            built = invoke([args.zig, 'cc', '-std=c11', '-O1', '-fsanitize=address,undefined',
                            '-fno-sanitize-recover=undefined', '-DMYLANG_NATIVE_PROVIDER=1', '-I', root / 'src',
                            cfile, root / 'tests/standard_io_provider.c', '-o', binary])
            assert built.returncode == 0, built.stderr
            scenarios = [({}, {'read': 3, 'collect': 99, 'write': 5}[fixture])]
            if fixture == 'read':
                scenarios += [({'IO_READ_FAIL': '1', 'IO_STALL': '1'}, 10), ({'IO_READ_FAIL': '2'}, 22)]
            if fixture == 'write':
                scenarios += [({'IO_WRITE_FAIL': '2'}, 5), ({'IO_WRITE_FAIL': '1', 'IO_STALL': '1'}, 5)]
            for settings, expected in scenarios:
                environment = {key: value for key, value in os.environ.items() if not key.startswith('IO_') and key != 'NATIVE_FAIL_ALLOCATION'}
                environment.update(settings)
                result = invoke([binary], environment)
                assert result.returncode == 0 and result.stdout == f'{expected}\n'.encode(), result
                assert b'io-live: 0 acquired: 1 released: 1' in result.stderr, result.stderr
                if fixture == 'write':
                    assert b'output: hello' in result.stderr, result.stderr
                attempts, _ = memory(result)
                count += 1
            if fixture == 'read':
                environment = {key: value for key, value in os.environ.items() if not key.startswith('IO_') and key != 'NATIVE_FAIL_ALLOCATION'}
                baseline = invoke([binary], environment)
                attempts, _ = memory(baseline)
                for failure in range(1, attempts + 1):
                    environment['NATIVE_FAIL_ALLOCATION'] = str(failure)
                    result = invoke([binary], environment)
                    if result.returncode == 0:
                        assert result.stdout == b'3\n', (failure, result)
                    else:
                        assert result.returncode == 2 and b'OutOfMemory' in result.stderr, (failure, result)
                    memory(result)
                    allocation_positions += 1
        print(f'Standard I/O native: {count} value/error/partial-progress comparisons and {allocation_positions} allocation failure positions passed')


if __name__ == '__main__':
    main()
