#!/usr/bin/env python3
"""Verify frozen standalone artifacts and record a branch walk, not execution."""
from pathlib import Path
import argparse, hashlib, json, re

parser = argparse.ArgumentParser()
parser.add_argument('--work', type=Path, default=Path(__file__).resolve().parents[2] / '.tmp-lox-byte-positive-20261003/refusal-diag')
work = parser.parse_args().work.resolve()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
inputs = json.loads((work / 'inputs.json').read_text())
original = (work / 'unsigned_le_w.ssa').read_text()
guard = inputs['variants']['unsigned_le_w']['guard']
assert original.count(guard) == 1
groups = [work, work / 'index-sign', work / 'control']
variants = {}
for group in groups:
    info = json.loads((group / 'inputs.json').read_text())
    compiled = json.loads((group / 'compiled.json').read_text())
    assert compiled['verified_after'] and compiled['inputs_sha256'] == sha(group / 'inputs.json')
    assert compiled['qbe_sha256'] == info['qbe_sha256'] == inputs['qbe_sha256']
    assert all(run['status'] == 0 for run in compiled['runs'])
    assert len(compiled['runs']) == 2 * len(info['variants'])
    for name, description in info['variants'].items():
        source, assembly, obj, disassembly = [group / (name + extension) for extension in ['.ssa', '.s', '.o', '.asm']]
        assert sha(source) == description['source_sha256']
        if description['guard'] is not None:
            assert source.read_text() == original.replace(guard, description['guard'])
        rows = [(int(address, 16), instruction.strip()) for address, instruction in re.findall(r'^\s*([0-9a-f]+):\s+([^\n]+)', disassembly.read_text(), re.M)]
        instructions = dict(rows)
        successor = {rows[index][0]: rows[index + 1][0] for index in range(len(rows) - 1)}
        address = rows[0][0]
        path, choices = [], []
        # Under IP=0, length=3: guard passes, index bound passes, increment fits.
        # Choices are recorded explicitly; this is not an emulator or a guest run.
        while True:
            instruction = instructions[address]
            path.append({'address': hex(address), 'instruction': instruction})
            operation = instruction.split()[0]
            assert operation not in ['call', 'ud2'] and len(path) < 100
            if operation == 'ret':
                break
            if operation == 'jmp':
                address = int(instruction.split()[1], 16)
            elif operation.startswith('j'):
                assert operation in ['je', 'jne', 'jb', 'jae', 'jg', 'jl']
                taken = operation == 'jb'
                choices.append({'address': hex(address), 'instruction': instruction, 'taken': taken})
                address = int(instruction.split()[1], 16) if taken else successor[address]
            else:
                address = successor[address]
        assert len(choices) == 3
        assert len([row for row in path if row['instruction'].startswith('movzbq (')]) == 1
        assert len([row for row in path if re.search(r'^mov\s+%[^,]+,0x18\(%rsi\)$', row['instruction'])]) == 1
        variants[name] = {
            'files': {p.name: sha(p) for p in [source, assembly, obj, disassembly]},
            'whole_function_instructions': len(rows),
            'successful_path_instructions': len(path),
            'branch_choices': choices, 'path': path,
            'admission': 'signed index >= 0 and unsigned index < length; extends huge-length domain' if name.startswith('index_') else ('canonical normalizer' if name == 'fixed_control' else 'unsigned length <= I64_MAX and unsigned index < length'),
        }

maximum = (1 << 63) - 1
mask = (1 << 64) - 1
lengths = [0, 1, maximum, 1 << 63, (1 << 63) + 1, mask]
indices = [-(1 << 63), -1, 0, 1, maximum]
signed = lambda value: value if value <= maximum else value - (1 << 64)
models = []
for length in lengths:
    predicates = {
        'unsigned_le_w': length <= maximum,
        'signed_ge_l': signed(length) >= 0,
        'signed_ge_w': signed(length) >= 0,
        'signed_lt_l': not signed(length) < 0,
        'length_lt_w': not signed(length) < 0,
        'high_shr_l': (length >> 63) == 0,
        'high_sar_l': (signed(length) >> 63) == 0,
        'unsigned_lt_min_l': length < (1 << 63),
    }
    assert len(set(predicates.values())) == 1
    for index in indices:
        bound = (index & mask) < length
        bounded_admission = length <= maximum and bound
        index_admission = index >= 0 and bound
        assert not bounded_admission or index >= 0
        assert not index_admission or index >= 0
        models.append({'length': length, 'index': index, 'length_predicates': predicates,
                       'bounded_admission': bounded_admission, 'index_admission': index_admission})
assert sum(row['bounded_admission'] != row['index_admission'] for row in models) == 9
expected = {'unsigned_le_w': 26, 'signed_ge_l': 25, 'signed_ge_w': 25, 'signed_lt_l': 25,
            'length_lt_w': 25, 'high_shr_l': 24, 'high_sar_l': 24, 'unsigned_lt_min_l': 26,
            'index_ge_l': 25, 'index_lt_l': 25, 'fixed_control': 21}
assert {name: value['successful_path_instructions'] for name, value in variants.items()} == expected
receipt = {'kind': 'static standalone assembly diagnostic; no guest execution, counters or timing',
           'assumptions': 'IP=0, length=3, readable receiver/storage, increment fits; includes endbr/prologue/ret',
           'compiler_production_files_changed': False, 'qbe_sha256': inputs['qbe_sha256'],
           'variants': variants, 'admission_boundary_model': models,
           'huge_length_scope': 'Length refusal preserves original normalizer; it is not itself a trap. Index-sign arms extend admission and need a separate certificate/SPEC review.',
           'verified_after': True}
output = work / 'analysis.json'
assert not output.exists()
output.write_text(json.dumps(receipt, indent=2) + '\n')
for name, result in variants.items():
    print(name, result['whole_function_instructions'], result['successful_path_instructions'])
