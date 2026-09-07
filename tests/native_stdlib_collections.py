"""Check borrowed/hash collection values and cleanup in both native optimization modes."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from native_memory import memory


def run(args, env=None):
    return subprocess.run(list(map(str, args)), capture_output=True, timeout=120, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    failures = 0
    with tempfile.TemporaryDirectory(prefix='stdlib-collections-') as temp:
        temp = Path(temp)
        for fixture in ('collection_borrows', 'hash_collections', 'word_counts', 'owned_collections', 'owned_buffer_mutations'):
            source = temp / 'main.my'
            text = (root / 'src/stdlib/fixtures' / (fixture + '.my')).read_bytes()
            source.write_bytes(text if text.startswith(b'module ') else b'module main;\n' + text)
            interpreted = run([compiler, 'run-project', source])
            assert (interpreted.returncode, interpreted.stdout) == (0, b'42\n'), interpreted.stderr
            emitted = run([compiler, 'emit-project-c', source])
            assert emitted.returncode == 0, emitted.stderr
            generated = temp / 'program.c'
            generated.write_bytes((root / 'tests/native_memory.h').read_bytes() + b'\n' + emitted.stdout)
            for mode in ('-O0', '-O2'):
                exe = temp / 'program'
                built = run(['cc', '-std=c11', mode, '-fsanitize=undefined', '-fno-sanitize-recover=all', generated, '-o', exe])
                assert built.returncode == 0, built.stderr
                env = dict(os.environ)
                env.pop('NATIVE_FAIL_ALLOCATION', None)
                result = run([exe], env)
                assert (result.returncode, result.stdout) == (0, b'42\n'), result.stderr
                attempts, _ = memory(result)
                for point in range(1, attempts + 1):
                    env['NATIVE_FAIL_ALLOCATION'] = str(point)
                    failed = run([exe], env)
                    memory(failed)
                    assert failed.returncode == 2 and failed.stdout == b'' and b'OutOfMemory' in failed.stderr, (fixture, point, failed.stderr)
                    failures += 1
    print(f'collections VM/native parity and {failures} allocation failures passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()
