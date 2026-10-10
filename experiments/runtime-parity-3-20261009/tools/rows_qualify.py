#!/usr/bin/env python3
"""Check every built row against every registered reference, without timing."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin', required=True, type=Path)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('rp3_rows', ROOT / 'experiments/new-core-s4-20261006/integration/measure_all46.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    settings = SimpleNamespace(bin=args.bin.resolve(), runner=args.runner.resolve())
    result = {'rows': {}, 'complete': False, 'passed': False}
    good = True
    for row in module.rows.UNITS:
        configs = module.rows.configurations(settings, row)
        cells = []
        for size, iterations in ((64, 7), (4096, 2)):
            checksums = set()
            outputs = {}
            for label, command in configs.items():
                proc = subprocess.run(['taskset', '-c', '8', *map(str, command(size, iterations))],
                                      capture_output=True, text=True, timeout=120)
                fields = proc.stdout.split()
                valid = proc.returncode == 0 and len(fields) == 2 and all(f.isdigit() for f in fields)
                if valid:
                    checksums.add(int(fields[0]))
                good = good and valid
                outputs[label] = {'status': proc.returncode, 'stdout': proc.stdout.strip(),
                                  'stderr': proc.stderr, 'valid': valid}
            same = len(checksums) == 1
            good = good and same
            cells.append({'size': size, 'iterations': iterations, 'same_checksum': same, 'outputs': outputs})
        result['rows'][row] = cells
        args.out.write_text(json.dumps(result, indent=1) + '\n')
        print(row + ': ' + ('pass' if all(c['same_checksum'] and all(o['valid'] for o in c['outputs'].values()) for c in cells) else 'FAIL'), flush=True)
    result.update(complete=True, passed=good)
    args.out.write_text(json.dumps(result, indent=1) + '\n')
    raise SystemExit(0 if good else 1)


if __name__ == '__main__':
    main()
