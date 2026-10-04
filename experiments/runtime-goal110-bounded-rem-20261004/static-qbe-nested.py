#!/usr/bin/env python3
"""Read-only pinned QBE nested-arm instructions and stack placement comparison."""
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
PINS = {'qbe': {'baseline': '6b7cd8aaa1c8bfd0bdcb921f6318c2d3202c38d7b25f62be60e0ed5d017ca48d',
                'candidate': '7d4480524c4a88fcbcea755c4fc50ec5a9f94191e4208f9761177cf894aa32e7'}}
KERNEL = 'myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934'


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
    parser.add_argument('--baseline-bin', type=Path, required=True)
    parser.add_argument('--candidate-bin', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    bins = {label: inspect(directory / 'collections-my-qbe', 'qbe', label)
            for label, directory in (('baseline', args.baseline_bin), ('candidate', args.candidate_bin))}
    regions = {'baseline': (0x101cb95, 0x10200b1), 'candidate': (0x101cb69, 0x1020085)}
    before, after = (bins[label]['functions'] for label in ('baseline', 'candidate'))
    assert before.keys() == after.keys()
    changed = [name for name in before if signature(before[name], 2) != signature(after[name], 2)]
    assert changed == [KERNEL, 'myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5']
    rows = {label: [row for row in binary['functions'][KERNEL] if regions[label][0] <= row[0] < regions[label][1]]
            for label, binary in bins.items()}
    assert len(rows['baseline']) == len(rows['candidate']) == 2648
    slots, exits, unchanged = [], [], 0
    def relative(row, label):
        start = regions[label][0]
        base = bins[label]['symbols'][KERNEL][0]
        return re.sub(re.escape(KERNEL) + r'\+0x([0-9a-f]+)',
                      lambda match: 'nested' + hex(base + int(match[1], 16) - start), row[2])
    def stackless(text):
        return re.sub(r'-0x[0-9a-f]+\(%rbp\)', 'STACK(%rbp)', text)
    for index, (left, right) in enumerate(zip(rows['baseline'], rows['candidate'])):
        assert right[0] - left[0] == -44
        a, b = relative(left, 'baseline'), relative(right, 'candidate')
        if a == b:
            unchanged += 1
        elif stackless(a) == stackless(b):
            slots.append({'instruction_index': index, 'baseline': a, 'candidate': b})
        else:
            assert re.match(r'(?:jmp|je)\s+<nested', a) and re.match(r'(?:jmp|je)\s+<nested', b)
            exits.append({'instruction_index': index, 'baseline': a, 'candidate': b})
    assert len(slots) == 1060 and len(exits) == 5
    roots = direct_targets(rows['candidate']); roots.discard(KERNEL)
    pending, closure, external = list(roots), set(), set()
    while pending:
        name = pending.pop()
        if name in closure or name in external:
            continue
        if name not in after:
            external.add(name); continue
        closure.add(name); pending += list(direct_targets(after[name]) - closure)
    assert not closure.intersection(changed)
    assert all(signature(before[name], 2) == signature(after[name], 2) for name in closure)
    report = {'schema': 'mylang-goal110-bounded-rem-qbe-nested-static-v1', 'status': 'complete',
              'helper_sha256': digest(Path(__file__).read_bytes()),
              'baseline_source_revision': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
              'candidate_source_revision': '5e97db47f08f667d97419abafd098df263a2aec3',
              'binaries': {label: {'path': binary['path'], 'sha256': binary['sha256'],
                                  'whole_text_bytes': binary['whole_text_bytes'],
                                  'batch_bytes': binary['symbols'][KERNEL][1],
                                  'batch_prologue': binary['functions'][KERNEL][:5],
                                  'assembly_sha256': digest(binary['assembly'].encode())}
                           for label, binary in bins.items()},
              'named_functions_compared': len(before), 'changed_instruction_functions': changed,
              'unchanged_named_functions': len(before) - len(changed),
              'nested_arm': {'regions': regions, 'instructions_each': 2648,
                             'same_instruction_sizes_and_register_sequence': True,
                             'identical_except_addresses': False, 'address_shift_bytes': -44,
                             'exact_after_local_address_normalization': unchanged,
                             'stack_address_changes': slots, 'shared_exit_address_changes': exits,
                             'normalized_sha256': {label: signature(data, 2) for label, data in rows.items()}},
              'nested_direct_call_and_tail_call_closure': sorted(closure), 'external_targets': sorted(external),
              'closure_instructions_identical_except_symbol_addresses': True,
              'observations': ['Batch stack frame grows0x1e68 to0x1e78 (+16bytes).',
                               'Nested arithmetic/register/instruction sequence has no added instructions; stack slots remap.',
                               'All401other named functions, including the direct native-call closure, retain normalized instructions.',
                               'Repeated QBE cost is a frame/placement interaction hypothesis, not a proven microarchitectural cause.'],
              'limitations': ['Five exits to shared kernel cleanup are paired by instruction position; complete batch differs elsewhere.',
                              'Indirect callbacks and external shared-library bodies are not resolved by direct-call closure.',
                              'Stack-offset differences are explicitly reported, not silently normalized as addresses.',
                              'No additional performance measurement is performed.']}
    for label, binary in bins.items():
        assert digest(Path(binary['path']).read_bytes()) == binary['sha256']
    with args.output.open('x') as output_file:
        output_file.write(json.dumps(report, indent=2) + '\n')
    print('PASS403functions/2648nested instructions:1060stack references remap,+16frame; native closure unchanged')


if __name__ == '__main__':
    main()
