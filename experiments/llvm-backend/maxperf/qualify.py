#!/usr/bin/env python3
"""Byte-exact valid-input gate for isolated maxperf executables."""
import argparse
import hashlib
import json
import random
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True)
    parser.add_argument('--binary', action='append', required=True)
    parser.add_argument('--work', required=True)
    parser.add_argument('--input', default='/tmp/rt2x')
    parser.add_argument('--json', required=True)
    args = parser.parse_args()
    work = Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    arms = {name: Path(path).resolve() for name, path in (item.split('=', 1) for item in args.binary)}
    oracle = Path(args.reference).resolve()
    golden = REPO / 'experiments/sexpr-port/golden'
    fixtures = {name: REPO / path for name, path in
                (line.split('\t') for line in (golden / 'manifest.tsv').read_text().splitlines())}
    extras = {'unicode': '(cafe "λ漢字😀" "a\\\"b")', 'empty': '',
              'numbers': '(0 -1 1.25 100nF 3.3V 10mil 1mm 10mA 2%)',
              'long-string': '(label "' + 'abc λ ' * 1500 + '")'}
    rng = random.Random(49019)
    atoms = ['alpha', 'beta', '"hello"', '"λ漢字😀"', '-42', '1.25', '3.3V', '100nF']
    def expression(depth=0):
        if depth >= 6 or rng.random() < .55:
            return rng.choice(atoms)
        return '(' + ' '.join(expression(depth + 1) for _ in range(rng.randrange(7))) + ')'
    for index in range(50):
        extras[f'generated-{index:02}'] = '\n'.join(expression() for _ in range(20))
    for name, text in extras.items():
        path = work / (name + '.sexp')
        path.write_text(text)
        fixtures[name] = path
    for name in ('input.sexp', 'input8.sexp'):
        fixtures[name] = Path(args.input) / name
    report = {'oracle': str(oracle), 'oracle_sha256': hashlib.sha256(oracle.read_bytes()).hexdigest(),
              'arms': {name: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                       for name, path in arms.items()}, 'cases': []}
    for name, path in fixtures.items():
        for render in (False, True):
            arguments = [str(path)] + (['--render'] if render else [])
            ref = subprocess.run([str(oracle), *arguments], capture_output=True, timeout=30)
            if ref.returncode != 0 or ref.stderr:
                raise RuntimeError(f'invalid oracle case {name}: {ref.returncode} {ref.stderr!r}')
            expected = golden / (name + '.txt')
            if render and expected.exists() and ref.stdout != expected.read_bytes() + b'\n':
                raise RuntimeError(f'oracle disagrees with committed golden: {name}')
            for arm, binary in arms.items():
                result = subprocess.run([str(binary), *arguments], capture_output=True, timeout=30)
                match = (result.returncode, result.stdout, result.stderr) == (0, ref.stdout, b'')
                report['cases'].append({'arm': arm, 'fixture': name, 'render': render,
                    'match': match, 'status': result.returncode,
                    'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                    'stderr': result.stderr.decode('utf8', 'replace')})
                if not match:
                    print(f'MISMATCH {arm} {name} render={render}', flush=True)
    report['total'] = len(report['cases'])
    report['passed'] = sum(case['match'] for case in report['cases'])
    Path(args.json).write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['passed']}/{report['total']} valid-input comparisons passed")
    return int(report['total'] != report['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
