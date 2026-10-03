#!/usr/bin/env python3
"""Profile named immutable Lox guests, checking exact outputs and identities."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'audit', REPO / 'experiments/lox-performance-audit-20261002/audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--arm', default='baseline-llvm')
    parser.add_argument('--cpu', type=int, default=10)
    parser.add_argument('--cases', default='vm/fib,vm/properties,vm/instantiation,'
                        'vm/string_equality,tree/binary_trees,tree/properties,tree/closures')
    args = parser.parse_args()
    work = args.work.resolve()
    manifest = json.loads((work / 'binaries.json').read_text())
    binary = Path(manifest['binaries'][args.arm])
    before = audit.sha(binary)
    guest_manifest = binary.with_suffix(binary.suffix + '.qbe-manifest.json')
    if guest_manifest.exists():
        symbols = {f['symbol']: f['name']
                   for f in json.loads(guest_manifest.read_text())['functions']}
        symbols_hash = audit.sha(guest_manifest)
    else:
        guest_manifest = work / 'symbols.json'
        symbols = json.loads(guest_manifest.read_text())
        symbols_hash = audit.sha(guest_manifest)
    dest = work / 'profiles' / args.arm
    dest.mkdir(parents=True, exist_ok=False)
    rows = []
    for identifier in args.cases.split(','):
        engine, name = identifier.split('/')
        case = next(audit.cases(work, 'timed', [engine], {name}))
        stem = identifier.replace('/', '-')
        data = dest / (stem + '.data')
        argv = ['taskset', '-c', str(args.cpu), 'perf', 'record', '-q',
                '-F', '499', '-e', 'cycles:u', '--call-graph', 'dwarf,8192',
                '-o', str(data), '--', str(binary), f'--engine={engine}', case['script']]
        waits = []
        audit.quiet(args.cpu, waits)
        result = audit.run(argv, audit.clean_env(), 120)
        checked = audit.checked(result, case)
        report = subprocess.check_output(
            ['perf', 'report', '-i', str(data), '--stdio', '--no-children',
             '--percent-limit', '0.1', '-F', 'overhead,symbol', '--call-graph', 'none'],
            text=True)
        (dest / (stem + '.report.txt')).write_text(report)
        locations = []
        for line in report.splitlines():
            match = re.match(r'\s*(\d+\.\d+)%\s+\[.\]\s+(.+)', line)
            if match:
                symbol = match[2].strip()
                locations.append({'self_pct': float(match[1]), 'symbol': symbol,
                                  'name': symbols.get(symbol, symbol)})
        assert audit.sha(binary) == before
        assert audit.sha(case['script']) == case['script_sha256']
        rows.append({'case': identifier, 'arm': args.arm, 'command': argv,
                     'binary_sha256': before, 'script_sha256': case['script_sha256'],
                     'symbols_path': str(guest_manifest), 'symbols_sha256': symbols_hash,
                     'verification': checked, 'record_stderr': result['stderr'].decode(),
                     'quiet_waits': waits, 'rows': locations})
        audit.save(dest / 'summary.json', rows)
        print(identifier, json.dumps(locations[:9]), flush=True)
    assert audit.sha(guest_manifest) == symbols_hash
    (dest / 'complete.json').write_text(json.dumps(
        {'verified_after': True, 'cases': len(rows), 'binary_sha256': before}, indent=2) + '\n')


if __name__ == '__main__':
    main()
