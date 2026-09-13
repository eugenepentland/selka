#!/usr/bin/env python3
"""Guest test discovery, typed assertions, deterministic inputs, and failure classification."""
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
    with tempfile.TemporaryDirectory(prefix='guest-tests-') as directory:
        entry = Path(directory) / 'main.my'
        cases = Path(directory) / 'cases.json'
        entry.write_text("""module main
export Pair
export test_ok
export test_bad
export test_trap
export test_value


class Pair:
    n: i64
    good: bool


def main() -> i64:
    return 0


def test_ok() -> bool:
    return True


def test_bad() -> bool:
    return False


def test_trap() -> i64:
    return 1 // 0


def test_value(n: i64) -> Pair:
    return Pair(n=n, good=True)
""")
        cases.write_text(json.dumps({'main::test_trap': {'expected': '0'},
                                    'main::test_value': {'arguments': {'n': '17'},
                                                         'expected': {'n': '17', 'good': True}}}))

        def invoke(pattern='*', expected_code=0):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/test_project.py'), str(entry),
                                     '--compiler', compiler, '--cases', str(cases), '--filter', pattern],
                                    capture_output=True, text=True, timeout=90)
            assert result.returncode == expected_code, (result.stdout, result.stderr)
            return json.loads(result.stdout)

        report = invoke(expected_code=1)
        rows = {row['name']: row for row in report['tests']}
        assert rows['main::test_ok']['status'] == 'passed'
        assert rows['main::test_bad']['actual'] is False
        assert rows['main::test_bad']['expected'] is True
        assert rows['main::test_bad']['location']['line'] == 22
        assert rows['main::test_trap']['status'] == 'trap'
        assert rows['main::test_value']['status'] == 'passed'
        assert invoke('*test_ok')['status'] == 'passed'
        assert invoke('*missing', 3)['status'] == 'empty'
        cases.write_text(json.dumps({'main::test_ok': {'skip': 'fixture unavailable'}}))
        assert invoke('*test_ok', 3)['tests'][0]['status'] == 'skipped'
        entry.write_text('module main\nimport provider\nexport test_sample\n\n\n'
                         'def main() -> i64:\n    return 0\n\n\n'
                         'def test_sample() -> bool:\n    return provider.sample(7) == 42\n')
        provider = entry.parent / 'provider.my'
        original = 'module provider\nexport sample\n\n\nhost def sample(x: i64) -> i64 effects(host)\n'
        provider.write_text(original)
        cases.write_text(json.dumps({'main::test_sample': {'providers': {'provider.my': 'module provider\nexport sample\n\n\n'
                                                                              'def sample(x: i64) -> i64:\n    return x + 35\n'}}}))
        mocked = invoke()
        assert mocked['tests'][0]['status'] == 'passed'
        assert len(mocked['tests'][0]['provider_snapshot_sha256']) == 64
        assert provider.read_text() == original
        cases.write_text(json.dumps({'main::test_sample': {'providers': {'main.my': 'module main\n'}}}))
        assert invoke(expected_code=2)['status'] == 'infrastructure-failure'
        cases.write_text(json.dumps({'main::test_sample': {'providers': {'provider.my': 'module provider\nexport sample\n\n\n'
                                                                              'def sample(x: i64) -> bool:\n    return True\n'}}}))
        assert invoke(expected_code=2)['status'] == 'infrastructure-failure'
        cases.write_text('{}')
        entry.write_text('module main\n\n\ndef main() -> i64:\n    return missing\n')
        assert invoke(expected_code=2)['status'] == 'infrastructure-failure'
    print('guest test workflow checks passed')


if __name__ == '__main__':
    main()
