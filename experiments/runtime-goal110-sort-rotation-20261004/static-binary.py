#!/usr/bin/env python3
"""Replay rotation code sizes and the complete QBE instruction comparison."""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-text-rf-host-20261004/.mylang-cache/goal110-join/join-runner/bin')
AFTER = ROOT / '.mylang-cache/goal110-rotation-debug/runner/bin'
PINS = {
    'llvm': {'baseline': '95a365b32a2e78d44535dc9cfaede1492e114dea3290981fab8478ad12eda111',
             'candidate': '15537a5ae589c78fd1bd6e4b03d0dec8cc1a0d44236b9753d5cf95f148c34e92'},
    'qbe': {'baseline': '9434945299cca7aae22bcfcd0ffca769473671b8251f98dedf411405c55c5873',
            'candidate': '93ec975f257d0d116807a83eb9f54916a8aa6e03c64d2623960fc72d6bf6a0ca'},
}
KERNEL = 'myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934'
SORTS = ('sort_bytes', 'sort_f64', 'sort_generic', 'sort_i64', 'sort_text', 'sort_u64')
NESTED_START, NESTED_END = 0x101caa5, 0x101ffc4


def digest(value):
    return hashlib.sha256(value).hexdigest()


def output(*args):
    return subprocess.check_output(args, text=True)


def inspect(path, backend, label):
    assert digest(path.read_bytes()) == PINS[backend][label]
    symbols, addressable = {}, {}
    for line in output('nm', '-S', '-n', str(path)).splitlines():
        fields = line.split()
        if len(fields) != 4:
            continue
        address, size = int(fields[0], 16), int(fields[1], 16)
        if fields[2].lower() == 't':
            symbols[fields[3]] = (address, size)
        # TLS offsets and small scalar constants must never become addresses.
        if size and address >= 0x1000000:
            addressable[address] = (size, fields[3])
    starts = sorted(addressable)
    def immediate(match):
        address = int(match[1], 16)
        index = bisect.bisect_right(starts, address) - 1
        if index >= 0 and address < starts[index] + addressable[starts[index]][0]:
            return '$@' + addressable[starts[index]][1] + '+' + hex(address - starts[index])
        return match[0]
    def normalized(instruction):
        reference = re.search(r'#\s*[0-9a-f]+ <([^>]+)>', instruction)
        if reference and '(%rip)' in instruction:
            instruction = instruction[:reference.start()].rstrip()
            instruction = re.sub(r'[-]?0x[0-9a-f]+\(%rip\)',
                                 lambda _: '@' + reference[1] + '(%rip)', instruction)
        instruction = re.sub(r'\b[0-9a-f]+ <([^>]+)>', lambda match: '<' + match[1] + '>', instruction)
        return re.sub(r'\$0x([0-9a-f]+)', immediate, instruction)
    assembly = output('objdump', '-d', '-w', '--no-show-raw-insn', str(path))
    functions, current = {}, None
    for line in assembly.splitlines():
        header = re.match(r'^([0-9a-f]+) <(.*)>:', line)
        if header:
            current = header[2]
            if current in symbols:
                functions[current] = []
            continue
        row = re.match(r'\s*([0-9a-f]+):\s+(.*)', line)
        if not row or current not in functions:
            continue
        address = int(row[1], 16)
        start, size = symbols[current]
        if address < start + size:
            functions[current].append((address, row[2], normalized(row[2])))
    text = re.search(r'\]\s+\.text\s+PROGBITS\s+\S+\s+\S+\s+(\S+)', output('readelf', '-SW', str(path)))
    return {'path': str(path.resolve()), 'sha256': PINS[backend][label],
            'whole_text_bytes': int(text[1], 16), 'symbols': symbols,
            'functions': functions, 'assembly': assembly}


def signature(rows, column):
    return digest(('\n'.join(row[column] for row in rows) + '\n').encode())


def direct_targets(rows):
    targets = set()
    for _, raw, _ in rows:
        if re.match(r'(?:call|jmp)\s', raw):
            target = re.search(r'<([^>]+)>', raw)
            if target:
                targets.add(re.sub(r'\+0x[0-9a-f]+$', '', target[1]))
    return targets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-bin', type=Path, default=BASE)
    parser.add_argument('--candidate-bin', type=Path, default=AFTER)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--assembly-dir', type=Path)
    args = parser.parse_args()
    binaries = {backend: {label: inspect(directory / ('collections-my-' + backend), backend, label)
                         for label, directory in (('baseline', args.baseline_bin), ('candidate', args.candidate_bin))}
                for backend in ('llvm', 'qbe')}
    qbe = binaries['qbe']
    before, after = qbe['baseline']['functions'], qbe['candidate']['functions']
    assert set(before) == set(after)
    changed, functions = [], {}
    for name in sorted(before):
        identical = signature(before[name], 2) == signature(after[name], 2)
        if not identical:
            changed.append(name)
        functions[name] = {
            label: {'address': hex(binary['symbols'][name][0]), 'bytes': binary['symbols'][name][1],
                    'address_mod64': binary['symbols'][name][0] % 64,
                    'instruction_count': len(binary['functions'][name]),
                    'normalized_instructions_sha256': signature(binary['functions'][name], 2),
                    'raw_instruction_operands_sha256': signature(binary['functions'][name], 1)}
            for label, binary in qbe.items()}
        functions[name]['identical_except_symbol_addresses'] = identical
    assert changed == list(SORTS)
    assert qbe['baseline']['symbols'][KERNEL] == qbe['candidate']['symbols'][KERNEL] == (0x1016ab0, 132860)
    nested = {label: [row for row in binary['functions'][KERNEL] if NESTED_START <= row[0] < NESTED_END]
              for label, binary in qbe.items()}
    assert len(nested['baseline']) == len(nested['candidate']) == 2649
    assert signature(nested['baseline'], 2) == signature(nested['candidate'], 2)
    roots = direct_targets(nested['candidate'])
    # A jump to shared batch_result cleanup is intra-function control flow,
    # not a recursive call that can execute every other workload branch.
    roots.discard(KERNEL)
    pending, closure, external = list(roots), set(), set()
    while pending:
        name = pending.pop()
        if name in closure or name in external:
            continue
        if name not in after:
            external.add(name)
            continue
        closure.add(name)
        pending += list(direct_targets(after[name]) - closure)
    assert not closure.intersection(SORTS)
    assert all(functions[name]['identical_except_symbol_addresses'] for name in closure)
    indirect = {name: [hex(address) for address, raw, _ in after[name]
                      if re.match(r'(?:call|jmp)\s+\*', raw)] for name in sorted(closure)}
    indirect = {name: addresses for name, addresses in indirect.items() if addresses}
    names = ('myl_native_list_sort', 'sort_u64')
    sizes = {backend: {label: {
        'path': binary['path'], 'sha256': binary['sha256'], 'whole_text_bytes': binary['whole_text_bytes'],
        'symbols': {name: {'address': hex(binary['symbols'][name][0]), 'bytes': binary['symbols'][name][1]}
                    for name in names}}
        for label, binary in pair.items()} for backend, pair in binaries.items()}
    candidate_sort = binaries['llvm']['candidate']['functions']['myl_native_list_sort']
    moves = [hex(address) for address, raw, _ in candidate_sort if re.search(r'\bcall\s.*<memmove(?:@plt)?>', raw)]
    assert moves
    report = {
        'schema': 'mylang-goal110-sort-rotation-binary-v1', 'status': 'pass',
        'candidate_source_revision': '8043c4d9e0ad907c8a1b9e8416a1e58815eef0df',
        'baseline_artifact_source_revision': '5a60ef1039aca32657ef5877a464eb8a81d6c115',
        'compiler_policy': 'Both hosts Debug; both guest sets retain ordinary ReleaseFast backend policy.',
        'sizes': sizes, 'llvm_bulk_memmove_call_sites': moves,
        'qbe_comparison': {
            'named_functions_compared': len(functions), 'changed_instruction_functions': changed,
            'functions': functions,
            'nested_arm': {'start': hex(NESTED_START), 'end_exclusive': hex(NESTED_END),
                           'instructions': 2649, 'direct_calls': sum(bool(re.match(r'call\s', row[1])) for row in nested['candidate']),
                           'normalized_instructions_sha256': signature(nested['candidate'], 2),
                           'identical_except_symbol_addresses': True},
            'nested_direct_call_and_tail_call_closure': sorted(closure),
            'closure_roots': sorted(roots), 'external_targets': sorted(external),
            'closure_intersects_changed_sort_routines': False, 'indirect_sites': indirect,
            'assembly_sha256': {label: digest(binary['assembly'].encode()) for label, binary in qbe.items()},
        },
        'normalization': [
            'Instruction mnemonics, operand order, registers, scalar constants, stack offsets and local branch offsets are retained.',
            'Only annotated code addresses, annotated RIP-relative symbol addresses and immediates inside known non-TLS symbol ranges are replaced by the same symbol plus offset.',
            'Instructions outside the nm symbol size, including inter-function alignment padding, are excluded; instruction padding inside a function is retained.',
        ],
        'observations': [
            'The complete QBE batch_result and its nested arm retain their start addresses, sizes and normalized instructions.',
            'Only six native sorting functions change normalized instructions; no nested direct-call/tail-call target changes instructions.',
            'Native code after the sort block shifts by 0x510 bytes, and generated data shifts by 0x1510 bytes; each shift changes 64-byte alignment by 16 bytes.',
            'The repeated QBE nested-large slowdown has no added nested instructions in this comparison. A code/data alignment or cache interaction is a hypothesis only.',
        ],
        'limitations': [
            'Static code equivalence does not prove a microarchitectural cause or exclude residual measurement effects.',
            'The direct-call/tail-call closure does not resolve indirect calls, callbacks or jump tables. Whole-guest comparison covers every named callback body; only sort routines differ.',
            'Intra-kernel jumps to shared cleanup are excluded from function closure; the complete kernel body, including that cleanup, is independently compared.',
            'External libc/shared-library bodies and anonymous data/jump-table contents are not compared here.',
            'There are no new performance measurements in this analysis; Debug-host screens do not establish ordinary goal acceptance.',
        ],
    }
    if args.assembly_dir:
        args.assembly_dir.mkdir(parents=True, exist_ok=True)
        for label, binary in qbe.items():
            (args.assembly_dir / ('qbe-' + label + '-full.asm')).write_text(binary['assembly'])
    if args.output:
        with args.output.open('x') as target:
            target.write(json.dumps(report, indent=2) + '\n')
    else:
        assert report == json.loads(Path(__file__).with_name('static-binary.json').read_text())
    print('PASS pinned LLVM bulk rotation/code sizes and QBE instruction comparison: ' + str(len(functions)) + ' functions, ' + str(len(closure)) + ' nested direct targets')


if __name__ == '__main__':
    main()
