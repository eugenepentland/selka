#!/usr/bin/env python3
"""Read-only symbol and relocation-normalized search code comparison."""
import argparse
import bisect
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess

KERNEL = 'myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect(binary, symbol, output, label):
    symbols_raw = subprocess.check_output(['nm', '-n', '-S', str(binary)], text=True)
    (output / (label + '-symbols.txt')).write_text(symbols_raw)
    symbols = []
    for line in symbols_raw.splitlines():
        match = re.match(r'([0-9a-f]+) ([0-9a-f]+) ([a-zA-Z]) (.*)', line)
        if match and int(match[2], 16):
            symbols.append((int(match[1], 16), int(match[2], 16), match[4]))
    symbols.sort()
    addresses = [row[0] for row in symbols]
    entry, size, _ = next(row for row in symbols if row[2] == symbol)
    raw = subprocess.check_output(['objdump', '-d', '--no-show-raw-insn',
                                   '--disassemble=' + symbol, str(binary)], text=True)
    (output / (label + '-' + symbol + '.asm')).write_text(raw)
    replacements, backedges, instructions = [], [], []

    def literal_immediate(match):
        value = int(match[1], 16)
        at = bisect.bisect_right(addresses, value) - 1
        if at >= 0:
            start, extent, name = symbols[at]
            if start <= value < start + extent and name.startswith('myl_lit_'):
                target = name + '+0x' + format(value - start, 'x')
                replacements.append({'immediate': hex(value), 'symbol': target})
                return '$<' + target + '>'
        return match[0]

    for line in raw.splitlines():
        match = re.match(r'\s*([0-9a-f]+):\s+(.*)', line)
        if not match:
            continue
        address, instruction = int(match[1], 16), match[2]
        jump = re.match(r'j\w+\s+([0-9a-f]+) <' + symbol +
                        r'(?:\+0x([0-9a-f]+))?>', instruction)
        if jump and int(jump[1], 16) < address:
            target = int(jump[1], 16)
            backedges.append({'from_offset': address - entry, 'target_offset': target - entry,
                              'target': hex(target), 'target_mod16': target % 16,
                              'target_mod32': target % 32, 'target_mod64': target % 64})
        # Keep the exact symbolic target including its offset. Only remove the
        # resolved absolute branch/call address and RIP displacement/address.
        instruction = re.sub(r'\b[0-9a-f]+ (?=<[^>]+>)', '', instruction)
        instruction = re.sub(r'-?0x[0-9a-f]+\(%rip\)', 'RIP(%rip)', instruction)
        instruction = re.sub(r'#\s*[0-9a-f]+\s+<', '# <', instruction)
        instruction = re.sub(r'\$0x([0-9a-f]+)', literal_immediate, instruction)
        instructions.append(f'{address - entry:04x}: {instruction}')
    normalized = '\n'.join(instructions) + '\n'
    (output / (label + '-' + symbol + '.normalized')).write_text(normalized)
    return normalized, {'entry': hex(entry), 'size': size, 'entry_mod16': entry % 16,
                        'entry_mod32': entry % 32, 'entry_mod64': entry % 64,
                        'instructions': len(instructions), 'literal_relocations': replacements,
                        'normalized_sha256': hashlib.sha256(normalized.encode()).hexdigest(),
                        'backedges': backedges}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    binaries = {'before': str(args.before.resolve()), 'after': str(args.after.resolve())}
    hashes = {label: digest(Path(path)) for label, path in binaries.items()}
    result = {'binaries': binaries, 'binary_hashes': hashes, 'symbols': {},
              'script_sha256': digest(Path(__file__)),
              'normalization': 'Instruction offsets, registers, nonrelocation immediates, '
              'and symbolic target names/offsets retained. Absolute branch/call addresses '
              'and RIP displacements removed; only immediate addresses proven by nm sizes '
              'to be within named myl_lit symbols become symbol+offset. No NOPs discarded.',
              'limit': 'Backward targets identify control-flow edges, not measured hotness. '
              'Instruction identity and changed addresses do not prove a performance cause.'}
    for symbol in ('myl_native_octets_find', 'index_walk', KERNEL):
        before, before_record = inspect(args.before, symbol, args.output, 'before')
        after, after_record = inspect(args.after, symbol, args.output, 'after')
        delta = ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                           fromfile='before', tofile='after'))
        (args.output / (symbol + '.diff')).write_text(delta)
        result['symbols'][symbol] = {'identical': before == after,
                                     'before': before_record, 'after': after_record}
    assert hashes == {label: digest(Path(path)) for label, path in binaries.items()}
    (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({symbol: row['identical'] for symbol, row in result['symbols'].items()}))


if __name__ == '__main__':
    main()
