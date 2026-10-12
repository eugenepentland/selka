#!/usr/bin/env python3
"""Prove a changed embedded oracle executes and fails in a private copied closure."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'experiments/development-loop-closeout-20261012/S03'
report = json.loads((BASE / 'inventory.json').read_text())
with tempfile.TemporaryDirectory(prefix='s03-oracle-', dir=ROOT / '.mylang-cache/s03-tmp') as directory:
    source = Path(directory)
    for entry in report['closure']:
        original = ROOT / entry['path']
        (source / original.name).write_bytes(original.read_bytes())
    fixture = source / 'number_grammar.txt'
    before = fixture.read_text()
    assert 'int|42|42\n' in before
    fixture.write_text(before.replace('int|42|42\n', 'int|42|43\n', 1))
    command = ['scripts/build-slot.sh', 'build', 'zig', 'test', str(source / 'text_scalar_root_test.zig')]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (BASE / 'mutated-oracle.log').write_text(result.stdout)
    assert result.returncode != 0, result.stdout
    assert 'expected 43, found 42' in result.stdout, result.stdout
    print(json.dumps({'mutation': 'int|42|42 -> int|42|43', 'returncode': result.returncode,
                      'expected': 'scalar oracle test fails, eight remaining tests execute'}))
