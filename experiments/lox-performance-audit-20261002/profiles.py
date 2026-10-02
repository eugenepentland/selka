#!/usr/bin/env python3
"""Collect profiles of the unchanged audit binaries and resolve guest symbols."""
import argparse
import json
from pathlib import Path
import re
import subprocess

import audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=10)
    args = parser.parse_args()
    work = args.work.resolve()
    output = work / 'profiles'
    output.mkdir(exist_ok=True)
    manifest = json.loads((work / 'binaries.json').read_text())
    symbols = json.loads((work / 'symbols.json').read_text())
    chosen = [('vm', 'fib'), ('vm', 'properties'), ('vm', 'instantiation'),
              ('vm', 'string_equality'), ('tree', 'binary_trees')]
    results = []
    for engine, name in chosen:
        case = next(audit.cases(work, 'timed', [engine], {name}))
        arms = ['mylang-llvm', 'zig']
        if (engine, name) == ('vm', 'properties'):
            arms.append('mylang-qbe')
        for arm in arms:
            binary = Path(manifest['binaries'][arm])
            before = audit.sha(binary)
            stem = f'{engine}-{name}-{arm}'
            data = output / (stem + '.data')
            command = ['taskset', '-c', str(args.cpu), 'perf', 'record', '-q',
                       '-F', '499', '-e', 'cycles:u', '--call-graph', 'dwarf,8192',
                       '-o', str(data), '--', str(binary), f'--engine={engine}', case['script']]
            waits = []
            audit.quiet(args.cpu, waits)
            result = audit.run(command, audit.clean_env(), 120)
            verification = audit.checked(result, case)
            report = subprocess.check_output(['perf', 'report', '-i', str(data), '--stdio',
                                               '--no-children', '--percent-limit', '0.1',
                                               '-F', 'overhead,symbol', '--call-graph', 'none'], text=True)
            (output / (stem + '.report.txt')).write_text(report)
            rows = []
            for line in report.splitlines():
                match = re.match(r'\s*(\d+\.\d+)%\s+\[.\]\s+(.+)', line)
                if match:
                    symbol = match[2].strip()
                    rows.append({'self_pct': float(match[1]), 'symbol': symbol,
                                 'name': symbols.get(symbol, symbol)})
            assert audit.sha(binary) == before, ('changed binary', arm)
            results.append({'case': case['id'], 'arm': arm, 'binary_sha256': before,
                            'script_sha256': case['script_sha256'], 'verification': verification,
                            'wall_s': result['wall_s'], 'record_stderr': result['stderr'].decode(),
                            'rows': rows})
            audit.save(output / 'summary.json', results)
            print(stem, rows[:8], flush=True)


if __name__ == '__main__':
    main()
