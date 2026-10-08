#!/usr/bin/env python3
"""Inspect pinned ELF bytes without rewriting inputs; prove surviving barrier removal."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-sort-rotation-20261004/.mylang-cache/goal110-rotation-debug/runner/bin')
AFTER = ROOT / '.mylang-cache/goal110-presize-ready-debug/runner/bin'
PINS = {
    'llvm': {'baseline': '15537a5ae589c78fd1bd6e4b03d0dec8cc1a0d44236b9753d5cf95f148c34e92',
             'candidate': 'a2b61a2ec1f336aedea734ff3b47eac1ffafd084ee53ed57672ded03581afdec'},
    'qbe': {'baseline': '93ec975f257d0d116807a83eb9f54916a8aa6e03c64d2623960fc72d6bf6a0ca',
            'candidate': '6a97f44864c2e329baa51024f8e6a3ece7653d9d118f54447dd6d7dbc94514aa'},
}
KERNEL = 'myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934'


def digest(value):
    return hashlib.sha256(value).hexdigest()


def output(*command):
    return subprocess.check_output(command, text=True)


def inspect(path, backend, label):
    expected = PINS[backend][label]
    assert digest(path.read_bytes()) == expected
    symbols = {}
    for line in output('nm', '-S', '--defined-only', str(path)).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2].lower() == 't':
            symbols[fields[3]] = (int(fields[0], 16), int(fields[1], 16))
    assembly = output('objdump', '-d', '-w', '--no-show-raw-insn', str(path))
    rows = [(int(match[1], 16), match[2]) for line in assembly.splitlines()
            if (match := re.match(r'\s*([0-9a-f]+):\s+(.*)', line))]
    start, size = symbols[KERNEL]
    kernel = [row for row in rows if start <= row[0] < start + size]
    def calls(selected, name):
        return [hex(address) for address, text in selected if re.match(r'call\s', text) and '<' + name + '>' in text]
    section = re.search(r'\]\s+\.text\s+PROGBITS\s+\S+\s+\S+\s+(\S+)', output('readelf', '-SW', str(path)))
    assert digest(path.read_bytes()) == expected  # inspection must remain read-only
    record = {'path': str(path.resolve()), 'sha256': expected, 'text_bytes': int(section[1], 16),
              'batch_address': hex(start), 'batch_bytes': size,
              'ordinary_calls_whole_guest': calls(rows, 'myl_rc_list_plain_ready'),
              'hot_calls_whole_guest': calls(rows, 'myl_rc_list_plain_ready_hot'),
              'ordinary_calls_batch': calls(kernel, 'myl_rc_list_plain_ready'),
              'hot_calls_batch': calls(kernel, 'myl_rc_list_plain_ready_hot'),
              'assembly_sha256': digest(assembly.encode())}
    return record, kernel, assembly


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--assembly-dir', type=Path)
    args = parser.parse_args()
    artifacts, kernels, assemblies = {}, {}, {}
    for backend in PINS:
        artifacts[backend], kernels[backend] = {}, {}
        for label, directory in (('baseline', BASE), ('candidate', AFTER)):
            record, rows, assembly = inspect(directory / ('collections-my-' + backend), backend, label)
            artifacts[backend][label], kernels[backend][label] = record, rows
            assemblies[backend + '-' + label + '.asm'] = assembly
    before, after = artifacts['llvm']['baseline'], artifacts['llvm']['candidate']
    assert len(before['ordinary_calls_whole_guest']) == 13 and len(after['ordinary_calls_whole_guest']) == 9
    assert len(before['ordinary_calls_batch']) == 8 and len(after['ordinary_calls_batch']) == 5
    assert not before['hot_calls_whole_guest'] and not after['hot_calls_whole_guest']
    warm = [row for row in kernels['llvm']['candidate'] if 0x1039a17 <= row[0] < 0x1039b2e]
    assert warm and not any(re.match(r'call\s', text) for _, text in warm)
    assert any('0xc8(%rdi)' in text for _, text in warm)  # pending-finalizer guard
    assert any('0x118(%rdi)' in text for _, text in warm)  # cached plain-word identity
    assert any('$0x4000000000000002' in text for _, text in warm) and any('$0xfffffffffffffffe' in text for _, text in warm)
    assert '0x1039edf' in after['ordinary_calls_batch']  # complete sort_int original fallback
    qbe_before, qbe_after = kernels['qbe']['baseline'], kernels['qbe']['candidate']
    def alias(rows):
        return [(address, re.sub(r'[0-9a-f]+ <myl_rc_list_plain_ready(?:_hot)?>', '<same_readiness_body>', text))
                for address, text in rows]
    assert alias(qbe_before) == alias(qbe_after)
    changes = [(hex(left[0]), left[1], right[1]) for left, right in zip(qbe_before, qbe_after) if left != right]
    assert len(changes) == 3
    report = {'schema': 'mylang-goal110-presize-ready-binary-v1', 'status': 'pass', 'artifacts': artifacts,
              'llvm_sort_int_inlined_admission_range': ['0x1039a17', '0x1039b2e'],
              'llvm_inlined_range_instructions': len(warm), 'llvm_inlined_range_no_calls': True,
              'llvm_sort_int_original_fallback_ordinary_call': '0x1039edf',
              'qbe_batch_identical_instructions_addresses_except_three_ready_callee_substitutions': True,
              'qbe_batch_callee_changes': changes,
              'limitations': ['Static inspection establishes surviving guard call removal and unchanged fallback presence, not performance.',
                              'LLVM register allocation/layout may change; QBE other functions/data and foreign libraries are outside this batch comparison.']}
    if args.assembly_dir:
        args.assembly_dir.mkdir(parents=True, exist_ok=True)
        for name, assembly in assemblies.items():
            with (args.assembly_dir / name).open('x') as target:
                target.write(assembly)
    if args.output:
        with args.output.open('x') as target:
            target.write(json.dumps(report, indent=2) + '\n')
    else:
        assert report == json.loads(Path(__file__).with_name('static-binary.json').read_text())
    print('PASS LLVM presize barrier removed; original fallback retained; QBE batch changes only three readiness callees')


if __name__ == '__main__':
    main()
