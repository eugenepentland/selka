"""End-to-end JSON workload timings; reports measurements without speed assertions."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def measured(command):
    started = time.perf_counter()
    result = subprocess.run([str(item) for item in command], capture_output=True, timeout=120)
    elapsed = time.perf_counter() - started
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return elapsed, result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--zig', required=True)
    parser.add_argument('--iterations', type=int, default=200)
    parser.add_argument('--samples', type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 10000 or not 1 <= args.samples <= 20:
        parser.error('iterations must be 1..10000 and samples 1..20')
    root = Path(__file__).resolve().parents[1]
    program = (root / 'src/native_fixtures/typed_json.my').read_text().replace('fn main(', 'fn once(')
    program += ('\nfn main(heap:allocator)->i64{let mut total=0;let mut i=0;'
                f'while i<{args.iterations}' + '{total+=once(heap);i+=1;}return total;}')
    with tempfile.TemporaryDirectory(prefix='native-json-bench-', dir=root / '.zig-cache') as temporary:
        directory = Path(temporary)
        entry, executable = directory / 'bench.my', directory / 'native'
        entry.write_text(program)
        build_seconds, _ = measured(['python3', root / 'scripts/native.py', entry, '--compiler', args.compiler.resolve(),
                                    '--zig', args.zig, '--mode', 'ReleaseFast', '-o', executable])
        commands = {'vm': [args.compiler.resolve(), 'run', entry, '--max-steps=100000000'],
                    'native': [executable, '--max-steps=100000000']}
        result = {'iterations': args.iterations, 'samples': args.samples, 'native_build_seconds': build_seconds}
        expected = f'{42 * args.iterations}\n'.encode()
        for backend, command in commands.items():
            timings = []
            for _ in range(args.samples):
                elapsed, output = measured(command)
                if output != expected:
                    raise RuntimeError((backend, output, expected))
                timings.append(elapsed)
            result[backend + '_median_seconds'] = statistics.median(timings)
        result['scope'] = 'process startup and execution; VM also loads/checks/compiles source; native compilation reported separately'
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
