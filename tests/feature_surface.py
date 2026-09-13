#!/usr/bin/env python3
"""Execute current reference examples and explicit exclusions against a pinned compiler."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    feature_run = subprocess.run([str(compiler), '--features'], capture_output=True, text=True, timeout=30)
    assert feature_run.returncode == 0, feature_run.stderr
    features = json.loads(feature_run.stdout)
    # The compiler reports its own build-time identity; it no longer hashes its executable.
    identity = features['compiler_sha256']
    assert isinstance(identity, str) and len(identity) == 64
    examples = []
    for document, expected in [('python-syntax.md', '42\n'), ('floating-point.md', '42\n'), ('source-evaluation.md', '45\n'), ('const-length-generics.md', '42\n'), ('bytes.md', '42\n')]:
        text = (ROOT / 'docs' / document).read_text()
        source = re.search(r'```(?:mylang|my)\n(.*?)\n```', text, re.S).group(1)
        examples.append((document, source, expected, None))
    for path, expected in [('arena-managed/main.my', '38\n'), ('callbacks.my', '17\n'), ('gc-default/main.my', '142\n'), ('python-bytes/main.my', '51\n'), ('python-word-count/main.my', '42\n')]:
        examples.append((path, (ROOT / 'examples' / path).read_text(), expected, None))
    examples.extend([
        ('unknown-f64-alias-excluded', 'fn main()->f64{return 0;}', '', 'E_UNKNOWN_TYPE'),
        ('stored-references-excluded', 'struct View{value:&i64}fn main()->i64{return 0;}', '', 'E_TYPE'),
        ('unresolved-hole-excluded', 'fn main()->i64{return todo<i64>();}', '', 'E_TYPED_HOLE'),
    ])
    rows = []
    with tempfile.TemporaryDirectory(prefix='feature-surface-') as temporary:
        path = Path(temporary) / 'main.my'
        for name, source, output, code in examples:
            path.write_text(source)
            action = 'check-project' if code else 'run-project'
            if not source.lstrip().startswith('module '):
                action = 'check' if code else 'run'
            reporting = [] if code else ['--print-result']
            result = subprocess.run([str(compiler), action, str(path), '--diagnostics=json', *reporting], capture_output=True, text=True, timeout=30)
            passed = result.returncode == (1 if code else 0) and result.stdout == output
            if code:
                codes = [json.loads(line)['diagnostic']['code'] for line in result.stderr.splitlines() if line.startswith('{')]
                passed = passed and code in codes
            else:
                passed = passed and not result.stderr
            rows.append({'case': name, 'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
                         'passed': passed, 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    recheck = subprocess.run([str(compiler), '--features'], capture_output=True, text=True, timeout=30)
    assert recheck.returncode == 0 and json.loads(recheck.stdout)['compiler_sha256'] == identity, 'compiler changed during acceptance'
    report = {'version': 'feature-surface-v1', 'compiler_sha256': identity, 'feature_report': features,
              'passed': all(row['passed'] for row in rows), 'cases': rows}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
