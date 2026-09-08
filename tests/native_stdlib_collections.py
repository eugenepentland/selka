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
    parser.add_argument('--zig', required=True)
    parser.add_argument('--fixture', help='run one named fixture instead of the suite')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    failures = 0
    with tempfile.TemporaryDirectory(prefix='stdlib-collections-') as temp:
        temp = Path(temp)
        for fixture in ('collection_borrows', 'hash_collections', 'word_counts', 'owned_collections', 'owned_buffer_mutations', 'library_parity', 'callback_context', 'callback_context_bounds'):
            if args.fixture and fixture != args.fixture:
                continue
            source = temp / 'main.my'
            text = (root / 'src/stdlib/fixtures' / (fixture + '.my')).read_bytes()
            source.write_bytes(text if text.startswith(b'module ') else b'module main;\n' + text)
            budget = ['--max-steps=100000000'] if fixture == 'callback_context_bounds' else []
            interpreted = run([compiler, 'run-project', source, *budget])
            assert (interpreted.returncode, interpreted.stdout) == (0, b'42\n'), interpreted.stderr
            emitted = run([compiler, 'emit-project-c', source])
            assert emitted.returncode == 0, emitted.stderr
            generated = temp / 'program.c'
            generated.write_bytes((root / 'tests/native_memory.h').read_bytes() + b'\n' + emitted.stdout)
            for mode in ('-O0', '-O2'):
                exe = temp / 'program'
                support = []
                if fixture == 'callback_context':
                    obj = temp / 'json-support.o'
                    built = run([args.zig, 'build-obj', root / 'src/native_json_bridge.zig',
                                 '-lc', '-fPIC', '-O', 'Debug' if mode == '-O0' else 'ReleaseFast',
                                 '-femit-bin=' + str(obj)])
                    assert built.returncode == 0, built.stderr
                    support.append(obj)
                driver = [args.zig, 'cc'] if support else ['cc']
                built = run([*driver, '-std=c11', mode, '-fsanitize=undefined', '-fno-sanitize-recover=all', generated, *support, '-lm', '-o', exe])
                assert built.returncode == 0, built.stderr
                env = dict(os.environ)
                env.pop('NATIVE_FAIL_ALLOCATION', None)
                result = run([exe, *budget], env)
                assert (result.returncode, result.stdout) == (0, b'42\n'), result.stderr
                attempts, _ = memory(result)
                if fixture == 'callback_context_bounds':
                    continue
                for point in range(1, attempts + 1):
                    env['NATIVE_FAIL_ALLOCATION'] = str(point)
                    failed = run([exe, *budget], env)
                    memory(failed)
                    if fixture == 'callback_context' and (failed.returncode, failed.stdout) == (0, b'42\n'):
                        failures += 1
                        continue
                    assert failed.returncode == 2 and failed.stdout == b'' and b'OutOfMemory' in failed.stderr, (fixture, point, failed.returncode, failed.stdout, failed.stderr)
                    failures += 1
    print(f'collections VM/native parity and {failures} allocation failures passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()
