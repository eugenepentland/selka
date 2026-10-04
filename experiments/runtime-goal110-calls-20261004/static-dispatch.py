"""Inspect the pinned LLVM ELF; this is static evidence, never a timing run.

The graph stops at the common batch-fold block. Cold branches outside that
range are recorded but not followed. Indirect fallback branches are recorded
but not decoded, so fallback counts are deliberately incomplete.
"""
import hashlib
import gzip
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
BINARY = ROOT / '.mylang-cache/goal110-calls-5dc31c3a-guests/compute-my-llvm'
EXPECTED = '5a009d03802013ca9df044e60f895da6400f71d54b76dd8cc4c6a1c546390d61'
DISPATCH = 0x102d081
FOLD = 0x102ea40
TABLE = 0x1009e90
CASES = ('integer_math', 'float_math', 'branch_predictable', 'branch_mixed',
         'record_construct', 'record_update', 'call_direct', 'call_indirect',
         'option_handle', 'result_propagate', 'binary_search', 'packet_decode')
SELECTED = (0, 1, 7, 6, 8, 4, 10, 9, 11, 5)

blob = BINARY.read_bytes()
assert hashlib.sha256(blob).hexdigest() == EXPECTED
assert blob[:6] == b'\x7fELF\x02\x01'
section_offset = struct.unpack_from('<Q', blob, 40)[0]
section_bytes, section_count = struct.unpack_from('<HH', blob, 58)
table_bytes = None
for ordinal in range(section_count):
    section = struct.unpack_from('<IIQQQQIIQQ', blob,
                                 section_offset + ordinal * section_bytes)
    address, offset, length = section[3:6]
    if address <= TABLE and TABLE + 12 * 8 <= address + length:
        table_bytes = blob[offset + TABLE - address:offset + TABLE - address + 12 * 8]
assert table_bytes is not None
targets = struct.unpack('<12Q', table_bytes)

disassembly = EVIDENCE / 'llvm-candidate-entry.s'
disassembly_bytes = (disassembly.read_bytes() if disassembly.exists()
                     else gzip.decompress(Path(str(disassembly) + '.gz').read_bytes()))
instructions = {}
for line in disassembly_bytes.decode().splitlines():
    fields = line.split('\t')
    if len(fields) >= 3 and re.fullmatch(r'\s*[0-9a-f]+:', fields[0]):
        address = int(fields[0].strip()[:-1], 16)
        instructions[address] = fields[2].strip()
ordered = sorted(instructions)
next_address = dict(zip(ordered, ordered[1:]))
assert instructions[DISPATCH] == 'jmp    *0x1009e90(,%rax,8)'
assert instructions[FOLD].startswith('mov')

records = []
for kind, (case, entry) in enumerate(zip(CASES, targets)):
    pending = [entry]
    visited = set()
    outside = set()
    edges = set()
    indirect = []
    while pending:
        pc = pending.pop()
        if not DISPATCH < pc < FOLD:
            outside.add(pc)
            continue
        if pc in visited:
            continue
        assert pc in instructions, hex(pc)
        visited.add(pc)
        instruction = instructions[pc]
        mnemonic = instruction.split()[0]
        if mnemonic.startswith('ret') or mnemonic == 'ud2':
            continue
        if mnemonic.startswith('j'):
            match = re.search(r'\s([0-9a-f]+)\s+<', instruction)
            if match:
                target = int(match[1], 16)
                edges.add((pc, target))
                pending.append(target)
            else:
                indirect.append([hex(pc), instruction])
            if mnemonic == 'jmp':
                continue
        if mnemonic == 'call' and 'myl_qbe_fail' in instruction:
            continue
        if pc in next_address:
            pending.append(next_address[pc])
    if kind in SELECTED:
        assert not indirect, (case, indirect)
    records.append({'case': case, 'kind': kind, 'selected': kind in SELECTED,
                    'entry': hex(entry), 'static_instructions_in_direct_cfg_scope': len(visited),
                    'backedges_in_scope': [[hex(a), hex(b)] for a, b in sorted(edges)
                                           if DISPATCH < b <= a < FOLD],
                    'indirect_jumps_in_scope': sorted(indirect),
                    'edges_outside_scope': [hex(pc) for pc in sorted(outside)],
                    'indirect_targets_followed': False})
receipt = {'kind': 'static-inner-loop-dispatch-proof-not-execution-count-or-kernel-cost',
           'source_revision': '5dc31c3af5114938fe1c92fc72941efd0b3074c3',
           'binary': str(BINARY), 'binary_sha256': EXPECTED,
           'disassembly_sha256': hashlib.sha256(disassembly_bytes).hexdigest(),
           'outer_batch_dispatch': hex(DISPATCH), 'common_batch_fold_scope_end': hex(FOLD),
           'table_address': hex(TABLE), 'table_bytes_hex': table_bytes.hex(),
           'selected_source_guard_order': list(SELECTED),
           'scope_limits': 'Direct control flow between the outer dispatch and common batch fold; cold external edges and indirect fallback targets are not followed. Counts include case setup and direct helper calls but exclude helper bodies. No dynamic instruction count or timing inference.',
           'baseline_repeated_dispatch': {'inner_header': '0x102cead', 'kind_load': '0x102ceb9',
                                          'indirect_jump': '0x102ced3', 'iteration_increment': '0x102ce9b',
                                          'inner_exit': '0x102d64d'},
           'records': records}
(EVIDENCE / 'llvm-dispatch-static.json').write_text(json.dumps(receipt, indent=2) + '\n')
print('Static LLVM dispatch proof: ten selected case graphs have no indirect jump; both excluded cases retain fallback dispatch.')
