"""Verify contract fixtures participate in ordinary project acceptance."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

IO_SOURCE = 'module io\n\n\n\n\n\npublic host def length() -> i64 effects(host)\n\n\npublic host def byte(index: i64) -> u8 effects(host)\n\n\npublic host def put(value: u8) -> i64 effects(host)\n'

MAIN_SOURCE = 'module main\nimport io\n\n\ndef main() -> i64:\n    index = 0\n    while index < io.length():\n        _ = io.put(io.byte(index))\n        index += 1\n    return 0\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--runner', required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='agent-tools-integration-') as temporary:
        base = Path(temporary)
        app = base / 'app'
        app.mkdir()
        (app / 'io.my').write_text(IO_SOURCE)
        (app / 'main.my').write_text(MAIN_SOURCE)
        (app / 'input.json').write_text('{"results":[1,2]}\n')
        expected = app / 'expected.json'
        expected.write_text('{"results": [1, 2]}')
        (app / 'cases.json').write_text(json.dumps({'version': 1, 'cases': [
            {'id': 'complete-results', 'input': 'input.json', 'expected': 'expected.json'}]}))
        for attempt, wanted_exit in enumerate((0, 1)):
            if attempt:
                expected.write_text('{"results": [1, 2, 3]}')
            contract_report = base / f'contract-{attempt}.json'
            manifest = app / 'verify.json'
            manifest.write_text(json.dumps({'version': 1, 'steps': [{
                'id': 'wire-contract', 'kind': 'test', 'commands': [[
                    sys.executable, str(ROOT / 'scripts/test_contract.py'),
                    '--fixtures', str(app / 'cases.json'), '--report', str(contract_report),
                    '--', str(args.runner.resolve()), '--project', str(app)]]}]}))
            project_report = base / f'project-{attempt}.json'
            result = subprocess.run([
                sys.executable, str(ROOT / 'scripts/project.py'),
                '--compiler', str(args.compiler.resolve()), '--entry', str(app / 'main.my'),
                '--manifest', str(manifest), '--report', str(project_report),
                '--cache-dir', str(base / 'cache')], capture_output=True, timeout=60)
            assert result.returncode == wanted_exit, (result.stdout, result.stderr)
            receipt = json.loads(result.stdout)
            assert len(result.stdout) < 8192, result.stdout
            assert receipt['version'] == 'project-feedback-v1', receipt
            assert receipt['identity_unchanged'], receipt
            assert receipt['verification']['step_counts']['selected'] == 1, receipt
            saved = json.loads(project_report.read_text())
            contract = json.loads(contract_report.read_text())
            assert contract['selected'] == contract['executed'] == 1, contract
            assert saved['status'] == contract['status'] == ('passed' if attempt == 0 else 'failed')
            assert ('failures' in receipt['verification']) == bool(attempt), receipt
    print('agent tools integration: contract success and incomplete-result rejection pass')


if __name__ == '__main__':
    main()
