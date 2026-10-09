#!/usr/bin/env python3
"""Selected entry typed census, keeping graph scope and omissions explicit."""
import argparse
import hashlib
import json
from pathlib import Path
from capture import capture
from count_typed import count, parse

parser = argparse.ArgumentParser()
parser.add_argument('compiler', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
workspace = Path(__file__).resolve().parents[4]
cost_root = Path(__file__).resolve().parents[1]
external = workspace / 'experiments/frontend-followthrough-20261009/external/sources'
selections = {
    'lox': (external / 'lox/benchmarks/lox/ports/mylang/main.my', external / 'lox'),
    'eda': (external / 'eda/mylang/src/main.my', external / 'eda/mylang'),
    'stdlib': (cost_root / 'operations/stdlib.my', workspace / 'src/stdlib'),
    'language': (cost_root / 'operations/main.my', cost_root / 'operations'),
}
compiler = args.compiler.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
summary = {}
for label, (entry, source_root) in selections.items():
    inputs = [compiler, entry]
    inputs += sorted(source_root.rglob('*.my'))
    inputs += sorted(source_root.rglob('mylang.json'))
    record, stdout, stderr = capture([str(compiler), 'dump-typed', str(entry)],
                                     output / label, cwd=workspace, inputs=set(inputs))
    result = {'entry': str(entry), 'selection': 'One selected executable entry; all checked body instances in its loaded graph.',
              'returncode': record['returncode'], 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest()}
    if record['returncode'] == 0:
        try:
            result.update(count(parse(stdout.decode())))
        except ValueError as error:
            result['walker_error'] = str(error)
    else:
        result['stderr'] = stderr.decode(errors='replace')
    (output / (label + '-counts.json')).write_text(json.dumps(result, indent=2) + '\n')
    summary[label] = {key: value for key, value in result.items() if key != 'events'}
(output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({label: {'returncode': result['returncode'], 'functions': result.get('functions'),
                         'walker_error': result.get('walker_error')} for label, result in summary.items()}, indent=2))
