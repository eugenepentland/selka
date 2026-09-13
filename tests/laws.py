#!/usr/bin/env python3
"""Seeded laws retain actual counterexamples and bounded reductions."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='guest-laws-') as directory:
        root = Path(directory)
        entry, config, output = (root / name for name in ('main.my', 'laws.json', 'report.json'))
        entry.write_text('module main\nexport test_law\n\n\n'
                         'def main() -> i64:\n    return 0\n\n\n'
                         'def test_law(n: i64) -> bool:\n    return n + n >= n\n')
        config.write_text(json.dumps({'main::test_law': {'n': [-30, -2]}}))
        command = [sys.executable, str(ROOT / 'scripts/laws.py'), str(entry), '--compiler', compiler,
                   '--laws', str(config), '--samples', '2', '--seed', '17', '--output', str(output)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        assert result.returncode == 1, (result.stdout, result.stderr)
        first = json.loads(output.read_text())
        assert first['passed'] is False
        assert len(first['cases']) == 2
        assert all(row['outcome']['status'] == 'failed' for row in first['cases'])
        assert all(-30 <= int(row['reduced_arguments']['n']) <= -2 for row in first['cases'])
        assert subprocess.run(command, capture_output=True, timeout=60).returncode == 1
        assert json.loads(output.read_text()) == first
        entry.write_text(entry.read_text().replace('n + n >= n', 'n - n == 0'))
        assert subprocess.run(command, capture_output=True, timeout=60).returncode == 0
        assert json.loads(output.read_text())['passed'] is True
    print('guest laws: repeatable sampled failures, bounded reduction, repaired law pass')


if __name__ == '__main__':
    main()
