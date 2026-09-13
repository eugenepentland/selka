#!/usr/bin/env python3
"""Execute header-index scaling acceptance through the actual compiler CLI."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-duplicate-scaling-') as directory:
        source = Path(directory) / 'scale.my'
        for size in (128, 512, 1024):
            declarations = [f'class D{i}:\n    pass\n' for i in range(size - 1)]
            for i in range(size):
                carrier = 0 if i == size - 1 else i
                declarations.append(
                    f'def f{i}(x: D{carrier}, y: i64) -> i64:\n    _ = x\n    return y * 2 + {i}\n')
            declarations.append('def main() -> i64:\n    return 0\n')
            source.write_text('\n'.join(declarations), encoding='utf-8')
            command = [args.compiler, 'discover-duplicates', str(source), '--approximate',
                       '--min-nodes=1', '--max-work=4000000']
            start = time.monotonic()
            first = subprocess.run(command, capture_output=True, text=True, timeout=90)
            assert first.returncode == 0, (size, first.returncode, first.stderr)
            assert '1 approximate pairs;' in first.stdout, (size, first.stdout)
            assert 'truncated=false' in first.stdout, (size, first.stdout)
            assert ' f0 ' in first.stdout and f' f{size - 1} ' in first.stdout, (size, first.stdout)
            second = subprocess.run(command, capture_output=True, text=True, timeout=90)
            assert second.returncode == 0, (size, second.stderr)
            assert first.stdout == second.stdout, (size, 'nondeterministic report')
            work = re.search(r'approximate near-v3:.*work=(\d+)/4000000;', first.stdout)
            assert work is not None, first.stdout
            print(f'duplicate header index: {size} functions, work={work.group(1)}, '
                  f'one distant pair, deterministic; two-run elapsed={time.monotonic() - start:.3f}s')

        for statements in (50, 100, 200):
            body = '    _ = x\n' * statements
            source.write_text(f'def a(x: i64) -> i64:\n{body}    return x * 2 + 1\n\n'
                              f'def b(x: i64) -> i64:\n{body}    return x * 2 + 3\n\n'
                              'def main() -> i64:\n    return 0\n', encoding='utf-8')
            command = [args.compiler, 'discover-duplicates', str(source), '--approximate',
                       '--min-nodes=1', '--max-work=4100000']
            result = subprocess.run(command, capture_output=True, text=True, timeout=90)
            assert result.returncode == 0, (statements, result.stderr)
            assert '1 approximate pairs;' in result.stdout, result.stdout
            assert 'truncated=false' in result.stdout, result.stdout
            assert '1 canonical-line edits' in result.stdout, result.stdout
            assert '- 1' in result.stdout and '+ 3' in result.stdout, result.stdout
            work = re.search(r'approximate near-v3:.*work=(\d+)/4100000;', result.stdout)
            assert work is not None, result.stdout
            print(f'duplicate banded distance: {statements} repeated statements, '
                  f'work={work.group(1)}, literal drift retained')


if __name__ == '__main__':
    main()
