#!/usr/bin/env python3
"""Read-only linked-code and translated-IR bindings for the floor-result experiment."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--native', type=Path, required=True)
parser.add_argument('--before-text', type=Path, required=True)
parser.add_argument('--after-text', type=Path, required=True)
parser.add_argument('--text-dump', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)


def artifact(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


def code(label, binary, name):
    manifest_path = Path(str(binary) + '.qbe-manifest.json')
    manifest = json.loads(manifest_path.read_text())
    function = next(function for function in manifest['functions'] if function['name'] == name)
    symbol = function['symbol']
    nm_command = ['nm', '-S', '--defined-only', str(binary)]
    nm = subprocess.check_output(nm_command, text=True)
    linked = next((line for line in nm.splitlines() if line.endswith(' ' + symbol)), None)
    record = {'binary': artifact(binary), 'manifest': artifact(manifest_path), 'function': function,
              'nm_command': nm_command, 'linked_symbol': linked}
    if linked:
        command = ['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + symbol, str(binary)]
        assembly = subprocess.check_output(command, text=True)
        path = out / (label + '.asm')
        path.write_text(assembly)
        record.update(assembly=artifact(path), command=command,
                      instructions=sum(bool(re.match(r'\s+[0-9a-f]+:\s+\w+', line)) for line in assembly.splitlines()),
                      sar63=len(re.findall(r'sar\s+\$0x3f', assembly)))
    return record


report = {'kind': 'actual-linked-floor-result-range-code', 'native': {}, 'text': {},
          'runner': artifact(Path(__file__)), 'limitation': 'Disassembly is linked O3/full-LTO guest code; Debug host is exploratory. No timing evidence or placement attribution.'}
names = ('main', 'recursive', 'floor_large', 'zero_bool', 'seeded_bool', 'signed_updates',
         'negative_divisor', 'variable', 'truncated')
for label in ('before', 'after'):
    work = args.native.resolve() / 'rc-v5-llvm-accounted0' / label
    report['native'][label] = {}
    manifest = json.loads((work / 'guest.qbe-manifest.json').read_text())
    for name in names:
        row = code(label + '-' + name, work / 'guest', name)
        symbol = row['function']['symbol']
        il_path, ir_path = work / 'dump' / (symbol + '.ssa'), work / 'dump' / (symbol + '.ll')
        assert il_path.is_file() and ir_path.is_file()
        il, ir = il_path.read_text(), ir_path.read_text()
        row.update(il=artifact(il_path), ir=artifact(ir_path), markers=il.count('# myl-floor-result'),
                   assumes=ir.count('call void @llvm.assume'))
        if label == 'after':
            assert row['markers'] == row['assumes']
            if name in ('negative_divisor', 'variable', 'truncated'):
                assert row['markers'] == 0
        else:
            assert row['markers'] == row['assumes'] == 0
        report['native'][label][name] = row
for label, binary in (('before', args.before_text.resolve()), ('after', args.after_text.resolve())):
    row = code(label + '-text-kernel', binary, 'main::kernel')
    if label == 'after':
        symbol = row['function']['symbol']
        il_path, ir_path = args.text_dump.resolve() / (symbol + '.ssa'), args.text_dump.resolve() / (symbol + '.ll')
        row.update(il=artifact(il_path), ir=artifact(ir_path), markers=il_path.read_text().count('# myl-floor-result'),
                   assumes=ir_path.read_text().count('call void @llvm.assume'))
        assert row['markers'] == row['assumes'] == 19
    report['text'][label] = row
report['code_observations'] = {
    'frozen_equality': 'G4 checksum104f1a0..104f1d8 uses signed64 multiply+mov/sar63/and/add correction; new104f190..104f1b3 uses unsigned32 multiply, no negative correction. Checksum arithmetic17→11 instructions (20→14 including inc/cmp/je loop bookkeeping); helper/list/header work remains.',
    'zero_bool': 'Function is inlined in native main. New zero-based loop10201c0..1020231 uses unsigned multiply/subtract and no floor correction; signed seeded loop101ff20..101ff71 and signed_updates1020110..1020177 still have checked-add jo and sar63/and/add correction.',
    'recursive': 'Actual recursive linked body keeps signed floor correction and checked-subtraction overflow/frame traps.',
    'layout': 'Text kernel starts0x104e7d0 in both; size0x3737→0x3717, frame unchanged. Other bodies and placement can change; no runtime cause/gain claimed.'}
report['status'] = 'passed'
(out / 'code-proof.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS actual native/text linked code and exact annotation→assumption bindings')
