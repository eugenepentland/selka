#!/usr/bin/env python3
"""Read-only linked search-loop and helper normalization, with constant bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


def invoke(argv):
    result = subprocess.run(argv, text=True, capture_output=True, check=True)
    assert not result.stderr
    return result.stdout


def elf_bytes(path, address, length):
    data = path.read_bytes()
    assert data[:5] == b'\x7fELF\x02' and data[5] == 1
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    for index in range(count):
        fields = struct.unpack_from('<IIQQQQQQ', data, offset + size * index)
        kind, _, file_at, virtual, _, file_size, _, _ = fields
        if kind == 1 and virtual <= address and address + length <= virtual + file_size:
            return data[file_at + address - virtual:file_at + address - virtual + length]
    raise ValueError('Address is outside file-backed ELF segments')


def normalize(raw, path, base):
    instructions, constants, backedges = [], [], []
    for line in raw.splitlines():
        match = re.match(r'\s*([0-9a-f]+):\s+(.*)', line)
        if not match:
            continue
        address, instruction = int(match[1], 16), match[2]
        rip = re.search(r'#\s+([0-9a-f]+)\s+<([^>]+)>', instruction)
        if rip:
            assert '(%rip)' in instruction
            target = int(rip[1], 16)
            opcode = instruction.split()[0]
            width = {'vpbroadcastq': 8, 'vmovdqa': 16}[opcode]
            value = elf_bytes(path, target, width).hex()
            constants.append({'instruction_offset': address - base, 'target': hex(target),
                              'symbol': rip[2], 'bytes': value, 'width': width})
            instruction = re.sub(r'-?0x[0-9a-f]+\(%rip\)', '@PCREL(%rip)', instruction)
            instruction = instruction[:instruction.index('#')].rstrip() + ' # bytes=' + value
        branch = re.search(r'\b([0-9a-f]+) <([^>]+)>', instruction)
        if branch:
            target, symbol = int(branch[1], 16), branch[2]
            if instruction.startswith('j'):
                instruction = instruction[:branch.start()] + '@' + hex(target - base)
                if target < address:
                    backedges.append({'source': hex(address), 'target': hex(target),
                                      'offset': target - base, 'mod64': target % 64})
            else:
                instruction = instruction[:branch.start()] + '@' + symbol
        instructions.append(instruction)
    return '\n'.join(instructions) + '\n', constants, backedges


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--after', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = {'status': 'passed', 'script': binding(Path(__file__)), 'variants': {}, 'comparisons': {},
          'normalization': 'Retain all opcodes, operands, NOPs and registers. Rebase branch targets; name call targets; replace RIP displacement only after binding exact loaded constant bytes from ELF LOAD segments.',
          'limitations': ['Static identity and placement differences do not establish a performance cause.',
                          'Index-walk suffix/prefix path is input dependent; recorded helper backedges are not a profile.']}
for label, binary, start, end in (('before', args.before, 0x104f550, 0x104f6e0),
                                ('after', args.after, 0x104f530, 0x104f6c0)):
    symbols = invoke(['nm', '-S', '--defined-only', str(binary)]).splitlines()
    variant = {'binary': binding(binary), 'functions': {}}
    for name in ('search_loop', 'myl_native_octets_find', 'index_walk', 'equal_large_octets'):
        if name == 'search_loop':
            entry, size = start, end - start
            command = ['objdump', '-d', '--no-show-raw-insn', '--start-address=' + hex(start),
                       '--stop-address=' + hex(end), str(binary)]
        else:
            symbol, = [line for line in symbols if line.split()[-1] == name]
            entry, size = [int(value, 16) for value in symbol.split()[:2]]
            command = ['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + name, str(binary)]
        raw = invoke(command)
        raw_path = args.output / (label + '-' + name + '.asm')
        raw_path.write_text(raw)
        normalized, constants, backedges = normalize(raw, binary, entry)
        norm_path = args.output / (label + '-' + name + '.normalized')
        norm_path.write_text(normalized)
        variant['functions'][name] = {'entry': hex(entry), 'mod64': entry % 64, 'bytes': size,
                                     'instructions': len(normalized.splitlines()), 'command': command,
                                     'assembly': binding(raw_path), 'normalized': binding(norm_path),
                                     'constant_loads': constants, 'backedges': backedges}
    report['variants'][label] = variant
for name in report['variants']['before']['functions']:
    before = report['variants']['before']['functions'][name]
    after = report['variants']['after']['functions'][name]
    equal = before['normalized']['sha256'] == after['normalized']['sha256']
    assert equal, name
    report['comparisons'][name] = {'normalized_equal': equal,
                                  'instructions': before['instructions'], 'bytes': before['bytes'],
                                  'entry_shift': int(after['entry'], 16) - int(before['entry'], 16)}
assert report['comparisons']['search_loop']['instructions'] == 102
report['conclusion'] = ('The102-instruction timed search loop and all three examined helpers are instruction-identical after explicit target/constant normalization. The caller moves32bytes; scanner remains64-byte aligned. Index-walk entry and its backedges move112bytes. Placement is a testable hypothesis, not an attributed cause.')
(args.output / 'search-proof.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report['comparisons'], indent=2))
