#!/usr/bin/env python3
"""Check fresh execution and edited failing verdicts with an unchanged compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

SOURCE = '''func answer() -> int:
    return 1

public func test_answer() -> bool:
    return answer() == 1

public func test_independent() -> bool:
    return True
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('output must be a new private directory')
    output.mkdir(parents=True)
    entry = output / 'control_test.my'
    entry.write_text(SOURCE)
    rows = []
    compiler = args.compiler.resolve()
    with admission('build'):
        for state, flags, edited in [('cold', [], False), ('warm', [], False), ('force', ['--force'], False), ('no-cache', ['--no-cache'], False), ('facts-leaks', ['--release', '--verify-facts'], False), ('edited-failure', [], True), ('forced-failure', ['--force'], True), ('reverted', [], False)]:
            entry.write_text(SOURCE.replace('return 1', 'return 2') if edited else SOURCE)
            command = [str(compiler), 'test', str(entry), '--json', '--zig', str(args.zig.resolve()), '--cache-dir', str(output / 'guest-cache'), *flags]
            environment = dict(os.environ)
            environment.pop('MYL_CORE_LEAKCHECK', None)
            if state == 'facts-leaks':
                environment['MYL_CORE_LEAKCHECK'] = '1'
            start = time.monotonic_ns()
            result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, timeout=120)
            (output / (state + '.stdout')).write_bytes(result.stdout)
            (output / (state + '.stderr')).write_bytes(result.stderr)
            record = json.loads(result.stdout)
            counts = {key: record.get(key) for key in ('passed', 'cached', 'failed', 'skipped', 'unsupported')}
            if len(record['tests']) != 2 or result.returncode != int(edited) or counts['failed'] != int(edited):
                raise RuntimeError('control verdict or inventory mismatch: ' + state)
            if state in ('force', 'no-cache', 'facts-leaks', 'forced-failure') and counts['cached']:
                raise RuntimeError('required fresh control replayed tests')
            if edited and not any(test['name'].endswith('::test_answer') and test['status'] == 'failed' for test in record['tests']):
                raise RuntimeError('changed answer failed the wrong test')
            row = {'state': state, 'command': command, 'status': result.returncode, 'counts': counts, 'leakcheck': environment.get('MYL_CORE_LEAKCHECK'), 'elapsed_ns': time.monotonic_ns() - start}
            rows.append(row)
            print(json.dumps(row), flush=True)
    (output / 'manifest.json').write_text(json.dumps({'version': 1, 'qualification': 'baseline operational controls only', 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'source_sha256': hashlib.sha256(SOURCE.encode()).hexdigest(), 'rows': rows}, indent=2) + '\n')


if __name__ == '__main__':
    main()
