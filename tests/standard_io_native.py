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
    temporary_root = root / '.mylang-cache/validation/tmp'
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=temporary_root, prefix='stdlib-io-') as tmp:
        directory = Path(tmp)
        count = 0
        allocation_positions = 0
        for fixture in ('read', 'collect', 'write', 'line', 'metadata', 'prebuffer', 'finish_retry', 'read_edges'):
            source = directory / 'main.my'
            source.write_bytes((root / 'src/stdlib/fixtures/io' / (fixture + '.my')).read_bytes())
            emitted = invoke([args.compiler.resolve(), 'emit-project-c', source])
            assert emitted.returncode == 0, emitted.stderr
            cfile = directory / 'guest.c'
            cfile.write_bytes((root / 'tests/native_memory.h').read_bytes() + b'\n' + emitted.stdout)
            binary = directory / 'guest'
            for mode in ('-O0', '-O2'):
                built = invoke([args.zig, 'cc', '-std=c11', mode, '-fsanitize=address,undefined',
                                '-fno-sanitize-recover=undefined', '-DMYLANG_NATIVE_PROVIDER=1', '-I', root / 'src',
                                cfile, root / 'tests/standard_io_provider.c', '-o', binary])
                assert built.returncode == 0, built.stderr
                scenarios = [({}, {'read': 3, 'collect': 99, 'write': 5, 'line': 98, 'metadata': 15, 'prebuffer': 42, 'finish_retry': 42, 'read_edges': 42}[fixture])]
                if fixture == 'read':
                    scenarios += [({'IO_READ_FAIL': '1', 'IO_STALL': '1'}, 10), ({'IO_READ_FAIL': '2'}, 22)]
                if fixture == 'write':
                    scenarios += [({'IO_WRITE_FAIL': '2'}, 5), ({'IO_WRITE_FAIL': '1', 'IO_STALL': '1'}, 5)]
                if fixture == 'line':
                    scenarios = [({'IO_INPUT': 'a\nb'}, 98)]
                if fixture == 'metadata':
                    scenarios += [({'IO_META_BAD': '1'}, -1), ({'IO_LIST_BAD': '1'}, -8)]
                if fixture == 'prebuffer':
                    scenarios = [({'IO_WRITE_FAIL': '2'}, 42)]
                if fixture == 'finish_retry':
                    scenarios = [({'IO_CLOSE_FAIL': '1'}, 42)]
                for settings, expected in scenarios:
                    environment = {key: value for key, value in os.environ.items() if not key.startswith('IO_') and key != 'NATIVE_FAIL_ALLOCATION'}
                    environment.update(settings)
                    result = invoke([binary], environment)
                    assert result.returncode == 0 and result.stdout == f'{expected}\n'.encode(), result
                    resources = 4 if fixture == 'metadata' and not settings.get('IO_META_BAD') else 1
                    assert f'io-live: 0 acquired: {resources} released: {resources}'.encode() in result.stderr, result.stderr
                    if fixture == 'write':
                        assert b'output: hello' in result.stderr, result.stderr
                    attempts, _ = memory(result)
                    count += 1
                if fixture in ('read', 'metadata'):
                    environment = {key: value for key, value in os.environ.items() if not key.startswith('IO_') and key != 'NATIVE_FAIL_ALLOCATION'}
                    baseline = invoke([binary], environment)
                    attempts, _ = memory(baseline)
                    for failure in range(1, attempts + 1):
                        environment['NATIVE_FAIL_ALLOCATION'] = str(failure)
                        result = invoke([binary], environment)
                        if result.returncode == 0:
                            assert result.stdout == baseline.stdout, (failure, result)
                        else:
                            assert result.returncode == 2 and b'OutOfMemory' in result.stderr, (failure, result)
                        memory(result)
                        allocation_positions += 1
        print(f'Standard I/O native: {count} value/error/partial-progress comparisons and {allocation_positions} allocation failure positions passed')


if __name__ == '__main__':
    main()
