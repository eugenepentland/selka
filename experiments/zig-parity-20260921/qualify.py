#!/usr/bin/env python3
"""Compare fresh Zig/mylang executables against the retained render goldens."""
import argparse
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def census_values(data):
    return {key: Decimal(value) for key, value in
            (field.split('=', 1) for field in data.decode().split())}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', action='append', required=True)
    parser.add_argument('--json', type=Path, required=True)
    options = parser.parse_args()
    binaries = dict(item.split('=', 1) for item in options.binary)
    goldens = ROOT / 'experiments/sexpr-port/golden'
    results = []
    for line in (goldens / 'manifest.tsv').read_text().splitlines():
        name, source = line.split('\t')
        path = ROOT / source
        # Goldens contain printer bytes; both command-line drivers append one
        # newline, as documented by the existing golden_compare.py harness.
        expected = (goldens / (name + '.txt')).read_bytes() + b'\n'
        census = None
        for arm, binary in binaries.items():
            for mode in ('census', 'render'):
                command = [str(Path(binary).resolve()), str(path)]
                if mode == 'render':
                    command.append('--render')
                process = subprocess.run(command, capture_output=True, timeout=60)
                assert process.returncode == 0 and not process.stderr, (name, arm, mode, process.returncode, process.stderr)
                if mode == 'render':
                    assert process.stdout == expected, (name, arm, 'render differs from retained golden')
                elif census is None:
                    census = process.stdout
                else:
                    # Empty/integer-valued sums print as `0` in Zig and `0.0`
                    # in mylang. Compare numeric fields, retaining byte hashes.
                    assert census_values(process.stdout) == census_values(census), (name, arm, 'census differs')
                results.append({'fixture': name, 'arm': arm, 'mode': mode,
                                'status': process.returncode,
                                'stdout_bytes': len(process.stdout),
                                'stdout_sha256': hashlib.sha256(process.stdout).hexdigest()})
    options.json.write_text(json.dumps({'fixtures': 17, 'runs': results,
                                       'goldens': 'all byte-identical',
                                       'census': 'equal numeric fields; integral float spelling may differ'}, indent=2) + '\n')
    print(f'Qualified {len(results)} executions: 17 render goldens and matching census outputs.')


if __name__ == '__main__':
    main()
