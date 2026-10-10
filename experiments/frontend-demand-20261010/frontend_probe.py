#!/usr/bin/env python3
"""Count fresh/replayed EDA frontend bodies without semantic-budget eviction."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.output / 'source'
    source.mkdir()
    for original in args.source.rglob('*.my'):
        target = source / original.relative_to(args.source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
    shutil.copy2(args.source / 'mylang.json', source / 'mylang.json')
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    environment['MYLANG_SEMANTIC_BUDGET'] = str(128 << 20)
    records = []
    with (args.output / 'stderr.log').open('w') as errors:
        process = subprocess.Popen(
            [str(args.compiler.resolve()), 'check-session', str(source.resolve() / 'main.my')],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
            text=True, env=environment)
        try:
            previous = {'checked': 0, 'reused': 0}
            for phase in ['cold', 'entry_edit', 'prefix_only']:
                entry = source / 'main.my'
                if phase == 'entry_edit':
                    text = entry.read_text()
                    assert text.count('    return status') == 1
                    entry.write_text(text.replace('    return status', '    return status + 0'))
                elif phase == 'prefix_only':
                    entry.write_text('\n' + entry.read_text())
                process.stdin.write('check\n')
                process.stdin.flush()
                record = json.loads(process.stdout.readline())
                assert record['status'] == 0, record
                record['phase'] = phase
                record['body_delta'] = {
                    field: record['functions'][field] - previous[field]
                    for field in previous}
                previous = {field: record['functions'][field] for field in previous}
                records.append(record)
                print(phase, record['body_delta'], flush=True)
            process.stdin.write('quit\n')
            process.stdin.flush()
            process.communicate(timeout=30)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
    (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')


if __name__ == '__main__':
    main()
