#!/usr/bin/env python3
"""Execute the complete native value fixture corpus with QBE and compare VM diagnostics."""
import argparse
from pathlib import Path
import sys
import tempfile
from native_cases import cases, invoke, signature

ROOT = Path(__file__).resolve().parents[1]


def compare(compiler, source, executable, options, name):
    vm = invoke([compiler, 'run', source, *options])
    native = invoke([executable, *options])
    try:
        assert signature(vm) == signature(native)
    except AssertionError as error:
        raise AssertionError((name, options, vm.returncode, vm.stdout, vm.stderr, native.returncode, native.stdout, native.stderr)) from error
    return vm.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    fixtures = cases(ROOT)
    comparisons = 0
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-native-cases-') as directory:
        directory = Path(directory)
        for index, (name, text) in enumerate(fixtures):
            source = directory / (name + '-"quoted.my')
            source.write_text(text)
            executable = directory / 'program'
            built = invoke([sys.executable, ROOT / 'scripts/qbe.py', source, '--compiler', compiler,
                            '--qbe', args.qbe, '--zig', args.zig, '--cache-dir', directory / 'cache', '-o', executable])
            assert built.returncode == 0, (name, built.returncode, built.stderr.decode(errors='replace'))
            normal = ['--max-frames=25000'] if name == 'recursive' else []
            for options in (normal, ['--max-steps=1'], ['--max-frames=1'], normal + ['--gc-stress']):
                compare(compiler, source, executable, options, name)
                comparisons += 1
            if name == 'calls' or name.startswith(('variant-', 'result-')):
                for budget in range(1, 200):
                    comparisons += 1
                    if compare(compiler, source, executable, [f'--max-steps={budget}'], name):
                        break
                else:
                    raise AssertionError((name, 'did not complete within acceptance budget'))
            if (index + 1) % 10 == 0:
                print(f'QBE native fixture parity: {index + 1}/{len(fixtures)} passed', flush=True)
    print(f'QBE native parity: {len(fixtures)} fixtures, {comparisons} VM comparisons; diagnostics, budgets, deep recursion and GC stress passed')


if __name__ == '__main__':
    main()
