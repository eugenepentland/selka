#!/usr/bin/env python3
"""Read-only counterfactual assembly, caller/helper and placement proof."""
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/goal110-search-placement'
OUT = WORK / 'proof'
OUT.mkdir(parents=True, exist_ok=True)
KERNEL = 'myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76'
FILL = b'\t.fill 32, 1, 0x90 # diagnostic placement counterfactual only\n'


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


def elf_bytes(data, address, length):
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    for index in range(count):
        fields = struct.unpack_from('<IIQQQQQQ', data, offset + size * index)
        kind, _, file_at, virtual, _, file_size, _, _ = fields
        if kind == 1 and virtual <= address and address + length <= virtual + file_size:
            return data[file_at + address - virtual:file_at + address - virtual + length]
    raise ValueError(hex(address))


def symbols(binary):
    raw = subprocess.check_output(['nm', '-S', '--defined-only', str(binary)], text=True)
    result = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) == 4:
            result[parts[3]] = {'address': int(parts[0], 16), 'size': int(parts[1], 16), 'kind': parts[2]}
    return raw, result


def canonical_offset(variant, name, offset):
    return offset - 32 if variant == 'fill32' and name == KERNEL and offset >= 0xd80 else offset


def pointer(variant, table, address):
    candidates = [(row['address'], row['size'], name) for name, row in table.items()
                  if row['size'] and row['address'] <= address < row['address'] + row['size']]
    if not candidates:
        return None
    at, _, name = max(candidates, key=lambda item: (item[0], -item[1], item[2]))
    return '@' + name + '+' + hex(canonical_offset(variant, name, address - at))


def normalize(variant, name, assembly, table, data):
    instructions, constants, fill = [], [], []
    entry = table[name]['address']
    for line in assembly.splitlines():
        match = re.match(r'\s*([0-9a-f]+):\s+(.*)', line)
        if not match:
            continue
        at, instruction = int(match[1], 16), match[2]
        if variant == 'fill32' and name == KERNEL and 0xd60 <= at - entry < 0xd80:
            assert instruction == 'nop'
            fill.append(at)
            continue
        rip = re.search(r'#\s+([0-9a-f]+)\s+<([^>]+)>', instruction)
        if rip:
            assert '(%rip)' in instruction
            target = int(rip[1], 16)
            opcode = instruction.split()[0]
            width = 1 if opcode.endswith('b') else 8
            if '%ymm' in instruction:
                width = 8 if opcode == 'vpbroadcastq' else 32
            elif '%xmm' in instruction:
                width = 16
            elif re.search(r'%e[a-z0-9]+', instruction):
                width = 4
            raw = elf_bytes(data, target, width)
            value = pointer(variant, table, int.from_bytes(raw, 'little')) if width == 8 else None
            value = value or raw.hex()
            constants.append({'offset': canonical_offset(variant, name, at - entry),
                              'address': hex(target), 'symbol': rip[2], 'width': width,
                              'raw_bytes': raw.hex(), 'canonical_value': value})
            instruction = re.sub(r'-?0x[0-9a-f]+\(%rip\)', '@PCREL(%rip)', instruction)
            instruction = instruction[:instruction.index('#')].rstrip() + ' # ' + rip[2] + ' value=' + value
        target = re.search(r'\b([0-9a-f]+) <([^>]+)>', instruction)
        if target:
            address, target_name = int(target[1], 16), target[2]
            if entry <= address < entry + table[name]['size']:
                reference = '@self+' + hex(canonical_offset(variant, name, address - entry))
            else:
                reference = '@' + target_name
            instruction = instruction[:target.start()] + reference
        immediate = re.search(r'\$0x([0-9a-f]+)', instruction)
        if immediate:
            reference = pointer(variant, table, int(immediate[1], 16))
            if reference:
                instruction = instruction[:immediate.start()] + reference + instruction[immediate.end():]
        instructions.append(instruction)
    if name == KERNEL and variant == 'fill32':
        assert fill == list(range(entry + 0xd60, entry + 0xd80))
    return '\n'.join(instructions) + '\n', constants, fill


report = {'kind': 'diagnostic-placement-static-proof', 'status': 'passed', 'driver': binding(Path(__file__)),
          'variants': {}, 'comparisons': {}, 'assembly_identity': {}, 'moved_symbols': [],
          'limitations': ['This counterfactual changes later placement as well as caller entry. No unique caller-address causal claim.',
                          'NOP fill executes at most on first fallthrough entry; repeated backedge skips it.',
                          'No timing or production adoption is claimed by static/correctness evidence.']}
tables = {}
for variant in ('capture', 'fill32'):
    build_path = WORK / variant / ('capture-build.json' if variant == 'capture' else 'fill-build.json')
    build = json.loads(build_path.read_text())
    assert build['exit_status'] == 0
    binary = Path(build['guest']['path'])
    assert binding(binary) == build['guest']
    raw_symbols, table = symbols(binary)
    tables[variant] = table
    (OUT / (variant + '-symbols.txt')).write_text(raw_symbols)
    calls = [json.loads(path.read_text()) for path in (WORK / variant / 'tool-calls').glob('*/call.json')]
    lto, = [call for call in calls if 'raw_assembly' in call]
    assembled, = [call for call in calls if 'annotated_assembly' in call]
    raw = Path(lto['used_assembly']['saved']['path'])
    annotated = Path(assembled['annotated_assembly']['saved']['path'])
    report['assembly_identity'][variant] = {'raw': binding(raw), 'annotated': binding(annotated),
                                           'lto_call': lto, 'assembly_call': assembled}
    functions = {}
    data = binary.read_bytes()
    for name in (KERNEL, 'myl_native_octets_find', 'index_walk', 'equal_large_octets'):
        command = ['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + name, str(binary)]
        assembly = subprocess.check_output(command, text=True)
        path = OUT / (variant + '-' + name + '.asm')
        path.write_text(assembly)
        normalized, constants, fill = normalize(variant, name, assembly, table, data)
        normalized_path = OUT / (variant + '-' + name + '.normalized')
        normalized_path.write_text(normalized)
        functions[name] = {'symbol': table[name], 'assembly': binding(path), 'command': command,
                           'normalized': binding(normalized_path), 'constant_loads': constants,
                           'instructions': len(normalized.splitlines()), 'removed_nop_addresses': fill}
    report['variants'][variant] = {'build': binding(build_path), 'binary': binding(binary), 'functions': functions}
for kind in ('raw', 'annotated'):
    before = Path(report['assembly_identity']['capture'][kind]['path']).read_bytes()
    after = Path(report['assembly_identity']['fill32'][kind]['path']).read_bytes()
    assert after.count(FILL) == 1 and after.replace(FILL, b'') == before
report['assembly_identity']['only_delta'] = 'One32-byte NOP .fill directive; raw and annotated complete assembly otherwise byte-identical, including frame metadata.'
for name, before in report['variants']['capture']['functions'].items():
    after = report['variants']['fill32']['functions'][name]
    equal = before['normalized']['sha256'] == after['normalized']['sha256']
    report['comparisons'][name] = {'normalized_equal': equal, 'instructions': before['instructions']}
    assert equal, name
for name, before in tables['capture'].items():
    after = tables['fill32'][name]
    assert before['kind'] == after['kind']
    assert before['size'] == after['size'] or (name == KERNEL and after['size'] == before['size'] + 32)
    if before['address'] != after['address'] or before['size'] != after['size']:
        report['moved_symbols'].append({'name': name, 'before': before, 'after': after,
                                        'shift': after['address'] - before['address']})
report['search_loop'] = {'capture': '0x104f530', 'fill32': '0x104f550', 'mod64': [48, 16],
                         'backedge_capture': '0x104f6ba', 'backedge_fill32': '0x104f6da',
                         'body_instructions': 102, 'body_bytes': 400}
path = OUT / 'placement-proof.json'
path.write_text(json.dumps(report, indent=2) + '\n')
print('PASS raw/annotated assembly only32NOPs; entire caller/helpers/constants normalized equal;',
      len(report['moved_symbols']), 'moved symbols')
