#!/usr/bin/env python3
"""Run only on the actual retired CLI under shared admission, in bounded batches."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--start', type=int, default=0)
parser.add_argument('--limit', type=int, default=10)
args = parser.parse_args()
compiler = args.compiler.resolve()
compiler_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
scratch = args.scratch.resolve()
scratch.mkdir(parents=True, exist_ok=True)
source = scratch / 'args.my'
source.write_text('func main(args: str[], out: Stream) -> int:\n    out.print(len(args))\n    return 0\n')
commands = [
    ['build', str(source)], ['run', str(source)], ['run-project', str(source)],
    ['check', str(source)], ['check', str(source), '--stats'],
    ['check-project', str(source)], ['check-module', str(source)],
    ['check-session'], ['lint', str(source)], ['dump-ir', str(source)],
    ['dump-typed', str(source)], ['test', str(source)], ['test', str(scratch)],
    ['cost', str(source)], ['coverage', str(source)], ['doctest', str(scratch)],
]
rows = []
for command in commands:
    for flag in ['--experimental-single-owner', '--experimental-zero-rc']:
        for suffix in ['', '=true']:
            rows.append((command + [flag + suffix], flag))
rows.append((['run', str(source), '--cache-dir', str(scratch / 'cache'), '--', '--experimental-zero-rc', '--experimental-single-owner'], None))
results = []
for command, flag in rows[args.start:args.start + args.limit]:
    invocation = [str(compiler), *command]
    result = subprocess.run(invocation, text=True, capture_output=True, input='', timeout=30)
    output = result.stdout + result.stderr
    if flag is None:
        passed = result.returncode == 0 and result.stdout == '2\n'
    else:
        passed = result.returncode == 2 and flag in output and 'was retired' in output and 'checked ownership is the default' in output
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != compiler_hash:
        raise RuntimeError('compiler changed during qualification')
    results.append(dict(argv=invocation, status=result.returncode, stdout=result.stdout, stderr=result.stderr, passed=passed))
report = dict(status='executed actual candidate; source deletion audits remain separate', compiler=str(compiler), compiler_sha256=compiler_hash, complete_matrix_rows=len(rows), start=args.start, rows=results, success=all(row['passed'] for row in results))
args.output.write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if report['success'] else 1)
