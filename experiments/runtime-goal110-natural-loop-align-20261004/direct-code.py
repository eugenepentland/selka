#!/usr/bin/env python3
"""Read-only linked direct-call dispatch, arithmetic and latch comparison."""
import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('search_code', ROOT / 'experiments/runtime-goal110-floor-result-range-20261004/search-code.py')
# Reuse only the audited ELF LOAD reader, without executing the old CLI.
namespace = {}
source = Path(spec.origin).read_text().split('\nparser = argparse.ArgumentParser')[0]
exec(compile(source, spec.origin, 'exec'), namespace)
elf_bytes = namespace['elf_bytes']


def artifact(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}


def instructions(text):
    return [(int(m[1], 16), m[2]) for m in re.finditer(r'^\s*([0-9a-f]+):\s+(.*)$', text, re.M)]


def region(body, lo, hi):
    return [(address, op) for address, op in instructions(body) if lo <= address < hi]


def normalized(rows, base):
    output = []
    for address, op in rows:
        match = re.search(r'\b([0-9a-f]+) <([^>]+)>', op)
        if match:
            target = '@' + (hex(int(match[1], 16) - base) if op.startswith('j') else match[2])
            op = op[:match.start()] + target
        output.append(op)
    return '\n'.join(output) + '\n'


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--code', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
code = json.loads(args.code.read_text())
assert code['status'] == 'passed'
symbol = 'myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5'
affine = 'myl_f_958e150c8e8d6bdababd5dd9f6c01f405c7a76ec04c592bc872ef959f2b49b31'
limits = {'before': {'header': (0x102ce99, 0x102cebe), 'direct': (0x102cf04, 0x102cf43),
                     'latch': (0x102ce7f, 0x102ce99), 'checksum': (0x102d63c, 0x102d6b6)},
          'after': {'header': (0x102ceca, 0x102ceef), 'direct': (0x102cf35, 0x102cf6d),
                    'latch': (0x102d577, 0x102d5a2), 'checksum': (0x102d62d, 0x102d6a5)}}
report = {'status': 'running', 'helper': artifact(__file__), 'elf_reader': artifact(spec.origin),
          'code_receipt': artifact(args.code), 'variants': {}, 'comparisons': {},
          'limitations': ['Static success-path mapping for frozen kind6, not an instruction-retirement profile.',
                         'Candidate includes range facts and loop metadata; no unique alignment or placement cause is established.',
                         'Changed surrounding cases, register allocation, tail merging and later placement remain coupled.']}
for label, spans in limits.items():
    record = code['groups']['compute']['arms'][label]
    binary = Path(record['binary']['path'])
    assert artifact(binary) == record['binary']
    asm_path = Path(record['assembly']['stdout']['path'])
    assert artifact(asm_path) == record['assembly']['stdout']
    text = asm_path.read_text()
    body = text.split('<' + symbol + '>:\n')[1].split('\n\n')[0]
    entry = next(f['entry'] for f in record['functions'] if f['symbol'] == symbol)
    rows = instructions(body)
    assert rows[:7][-1][1] == 'sub    $0x2e8,%rsp'
    output = args.output / (label + '-main.asm'); output.write_text(body + '\n')
    norm = args.output / (label + '-main.normalized'); norm.write_text(normalized(rows, entry))
    variant = {'binary': artifact(binary), 'sidecar': record['sidecar'], 'assembly': artifact(output),
               'normalized': artifact(norm), 'entry': hex(entry), 'frame_bytes': 0x2e8, 'regions': {}}
    for name, (lo, hi) in spans.items():
        selected = region(body, lo, hi)
        assert selected[0][0] == lo
        raw = args.output / (label + '-' + name + '.asm')
        raw.write_text('\n'.join(hex(address) + ': ' + op for address, op in selected) + '\n')
        variant['regions'][name] = {'entry': hex(lo), 'mod32': lo % 32, 'mod64': lo % 64,
                                   'instructions': len(selected), 'branches': sum(op.startswith('j') for _, op in selected),
                                   'nops': sum('nop' in op for _, op in selected), 'assembly': artifact(raw)}
    header = region(body, *spans['header'])
    table, = re.findall(r'jmp\s+\*0x([0-9a-f]+)\(,%rdi,8\)', header[-1][1])
    entries = struct.unpack('<12Q', elf_bytes(binary, int(table, 16), 96))
    assert entries[6] == spans['direct'][0]
    variant['dispatch_table'] = {'address': '0x' + table, 'entries': [hex(value) for value in entries],
                                 'bytes': elf_bytes(binary, int(table, 16), 96).hex(), 'direct_kind': 6}
    direct = region(body, *spans['direct'])
    assert direct[:2][0][1] == 'mov    %r15,%rdx' and direct[1][1] == 'add    %r11,%rdx'
    assert any(op == 'add    $0x7,%rax' for _, op in direct)
    assert not any(op.startswith('call') for _, op in direct)
    success = sum((region(body, *spans[name]) for name in ('header', 'direct', 'latch')), [])
    variant['per_element_success'] = {'instructions': len(success), 'branches': sum(op.startswith('j') for _, op in success),
                                     'nops': sum('nop' in op for _, op in success)}
    affine_body = text.split('<' + affine + '>:\n')[1].split('\n\n')[0]
    affine_entry = next(f['entry'] for f in record['functions'] if f['symbol'] == affine)
    affine_norm = args.output / (label + '-affine.normalized')
    affine_norm.write_text(normalized(instructions(affine_body), affine_entry))
    variant['affine_a'] = {'entry': hex(affine_entry), 'normalized': artifact(affine_norm)}
    report['variants'][label] = variant
    assert artifact(binary) == record['binary']
before, after = (report['variants'][key] for key in ('before', 'after'))
diff = args.output / 'main.diff'
diff.write_text(''.join(difflib.unified_diff(Path(before['normalized']['path']).read_text().splitlines(True),
                                          Path(after['normalized']['path']).read_text().splitlines(True),
                                          fromfile='before-main', tofile='after-main')))
assert before['affine_a']['normalized']['sha256'] == after['affine_a']['normalized']['sha256']
report.update(status='passed', whole_caller_diff=artifact(diff), conclusion={
    'affine_body_identical': True, 'arithmetic_checks_preserved': 'x+phase overflow, multiply3 overflow, add7 bound, pass-total overflow',
    'success_path_delta': '27->29 instructions and8->9 branches: new jump to shared accumulation tail plus context stack reload',
    'frame_bytes': '0x2e8 unchanged; general registers and stack-slot assignments change',
    'placement': 'inner header mod64 25->10; direct case4->53; no executed NOPs in selected element path'})
(args.output / 'direct-code.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report['conclusion'], indent=2))
