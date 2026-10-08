#!/usr/bin/env python3
"""Preserve exact reduced trap diagnostics across immutable compiler references."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--oracle', action='append', required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=False)
    root = Path.cwd()
    report = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), 'oracles': {}, 'cases': {}}
    environment = {**os.environ, 'MYL_CORE_LEAKCHECK': '1'}
    def execute(command, expected, log):
        start = time.monotonic()
        run = subprocess.run(list(map(str, command)), env=environment, capture_output=True, text=True, timeout=600)
        record = {'command': list(map(str, command)), 'exit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr, 'seconds': time.monotonic()-start}
        log.write_text(json.dumps(record, indent=2)+'\n')
        if run.returncode != expected:
            raise ValueError(f'expected {expected}: {log}')
        return record
    for argument in args.oracle:
        label, raw = argument.split('=', 1)
        compiler = Path(raw).resolve()
        before = hashlib.sha256(compiler.read_bytes()).hexdigest()
        report['oracles'][label] = {'path': str(compiler), 'sha256': before}
        for case in ('assert', 'result'):
            for mode in ('debug', 'release'):
                stem = f'{case}-{mode}-{label}'
                cache = root/'.mylang-cache/s4-emission'/args.evidence.name/stem
                output = cache/'program'
                command = [compiler, 'build', (args.fixtures/case/'app.my').resolve(), '-o', output, '--cache-dir', cache/'cache']
                if mode == 'release': command.append('--release')
                execute(command, 0, args.evidence/f'build-{stem}.json')
                result = execute([output], 1, args.evidence/f'run-{stem}.json')
                report['cases'].setdefault(f'{case}-{mode}', {})[label] = result['stderr']
                print(stem, repr(result['stderr']), flush=True)
        if hashlib.sha256(compiler.read_bytes()).hexdigest() != before: raise ValueError(f'compiler changed: {label}')
    (args.evidence/'summary.json').write_text(json.dumps(report, indent=2)+'\n')

if __name__ == '__main__': main()
