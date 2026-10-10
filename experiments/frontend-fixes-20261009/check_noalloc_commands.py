#!/usr/bin/env python3
"""Record F1's user-command behavior; raw output is kept only on failure."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    rows = []
    with tempfile.TemporaryDirectory(prefix='f1-commands-') as temporary:
        root = Path(temporary)
        (root / 'main.my').write_text('public func main(out: Stream) -> int noalloc:\n    const xs = [1]\n    out.print(xs)\n    return 0\n')
        (root / 'tests.my').write_text('func bounded() -> int noalloc:\n    const xs = [1]\n    return len(xs)\npublic func test_one() -> bool:\n    return bounded() == 1\n')
        commands = [('check', ['check', 'main.my'], 0, ''),
                    ('check-project', ['check-project', 'main.my'], 0, ''),
                    ('build', ['build', 'main.my', '-o', 'app'], 0, 'W_NOALLOC_ALLOCATES'),
                    ('run', ['run', 'main.my'], 0, 'W_NOALLOC_ALLOCATES'),
                    ('build --run', ['build', 'main.my', '--run'], 0, 'W_NOALLOC_ALLOCATES'),
                    ('test', ['test', 'tests.my'], 0, 'W_NOALLOC_ALLOCATES'),
                    ('test replay', ['test', 'tests.my'], 0, 'W_NOALLOC_ALLOCATES'),
                    ('lint', ['lint', 'main.my'], 0, 'L_NOALLOC_ALLOCATES'),
                    ('lint --gate', ['lint', 'main.my', '--gate'], 3, 'L_NOALLOC_ALLOCATES'),
                    ('cost', ['cost', 'main.my'], 0, '')]
        for name, command, expected_status, code in commands:
            result = subprocess.run([str(compiler), *command], cwd=root, capture_output=True)
            stderr = result.stderr.decode(errors='replace')
            stdout = result.stdout.decode(errors='replace')
            ok = result.returncode == expected_status and (code in stderr if code else name == 'cost' or 'NOALLOC' not in stderr)
            sites = re.findall(r'allocations (\d+)', stdout) if name == 'cost' else []
            if name == 'cost':
                ok = ok and bool(sites) and int(sites[-1]) > 0
            row = {'command': name, 'status': result.returncode, 'expected_status': expected_status,
                   'diagnostic_code': code, 'warning_count': stderr.count('W_NOALLOC_ALLOCATES'),
                   'lint_count': stderr.count('L_NOALLOC_ALLOCATES'), 'passed': ok,
                   'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                   'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()}
            if sites:
                row['allocation_sites'] = int(sites[-1])
            rows.append(row)
            if not ok:
                args.output.with_name('failed-' + name.replace(' ', '-') + '.stdout').write_bytes(result.stdout)
                args.output.with_name('failed-' + name.replace(' ', '-') + '.stderr').write_bytes(result.stderr)
        args.output.write_text(json.dumps({'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                                          'commands': rows}, indent=2) + '\n')
    print(json.dumps(rows, indent=2))
    return int(not all(row['passed'] for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
