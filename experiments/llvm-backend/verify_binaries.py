#!/usr/bin/env python3
"""Verify prebuilt benchmark arms against an oracle, goldens, and GC stress."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[2]
GOLDEN = REPO / 'experiments/sexpr-port/golden'
SPECIAL = {
    'unicode': '(café "λ漢字😀" "a\\\"b")'.encode(),
    'unterminated': b'(foo "oops', 'close': b')', 'unclosed': b'(a',
    'empty': b'', 'invalid-utf8': b'("\xff")',
    'numbers': b'(0 -1 1.25 100nF 3.3V 10mil 1mm 10mA 2%)',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', action='append', required=True, metavar='NAME=PATH')
    parser.add_argument('--reference', default='qbe')
    parser.add_argument('--work', required=True)
    parser.add_argument('--json', required=True)
    options = parser.parse_args()
    arms = {}
    for item in options.binary:
        name, separator, path = item.partition('=')
        if not name or not separator or name in arms or not Path(path).is_file():
            parser.error(f'invalid or duplicate binary {item!r}')
        arms[name] = Path(path).resolve()
    if options.reference not in arms:
        parser.error('reference must name a supplied binary')
    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)
    fixtures = {name: Path(path) for name, path in
                (line.split('\t') for line in (GOLDEN / 'manifest.tsv').read_text().splitlines())}
    for name, raw in SPECIAL.items():
        path = work / (name + '.sexp')
        path.write_bytes(raw)
        fixtures[name] = path
    report = {'reference': options.reference, 'cases': [],
              'stress_scope': 'both census and render for every fixture below 2000 bytes',
              'arms': {name: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                       for name, path in arms.items()}}
    for name, path in fixtures.items():
        for render in (False, True):
            arguments = [str(path)] + (['--render'] if render else [])
            ref = subprocess.run([str(arms[options.reference]), *arguments], capture_output=True, timeout=60)
            expected = (ref.returncode, ref.stdout, ref.stderr)
            if ref.returncode < 0:
                raise SystemExit(f'oracle crashed: {name}, render={render}')
            for arm, binary in arms.items():
                for stress in ((False, True) if path.stat().st_size < 2000 else (False,)):
                    result = subprocess.run([str(binary), *(['--gc-stress'] if stress else []), *arguments],
                                            capture_output=True, timeout=60)
                    match = (result.returncode, result.stdout, result.stderr) == expected
                    golden = GOLDEN / (name + '.txt')
                    if render and golden.exists():
                        match = match and result.returncode == 0 and result.stdout == golden.read_bytes() + b'\n'
                    report['cases'].append({'arm': arm, 'fixture': name, 'render': render,
                                            'stress': stress, 'match': match, 'status': result.returncode,
                                            'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                                            'stderr': result.stderr.decode('utf8', 'replace')})
                    if not match:
                        print('MISMATCH', arm, name, render, stress, flush=True)
    report['passed'] = sum(case['match'] for case in report['cases'])
    report['total'] = len(report['cases'])
    Path(options.json).write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['passed']}/{report['total']} benchmark comparisons passed")
    return int(report['passed'] != report['total'])


if __name__ == '__main__':
    raise SystemExit(main())
