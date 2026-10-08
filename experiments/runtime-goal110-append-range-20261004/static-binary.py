#!/usr/bin/env python3
"""Inspect immutable append6910 SSA and ELF inputs using read-only tools."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-presize-ready-20261004/.mylang-cache/goal110-presize-ready-debug/runner')
AFTER = ROOT / '.mylang-cache/goal110-append-range-debug/runner'
REVISIONS = {'baseline': '63842d3c32ab3079d878cff89224478543f9b7f3',
             'candidate': '6910e08351a50ce8524a5e37d3f6c23feb4d3383'}
MANIFESTS = {'baseline': 'b34888b317276dd7f274332c7d757196583ffc7e003b2f9efa10b0aeac7829bc',
             'candidate': '9726b7b3dbd48a5b3c4399f6a1990276f3615b56b2c18787213fa175ccb49f63'}
PINS = {
    'llvm': {'baseline': 'a2b61a2ec1f336aedea734ff3b47eac1ffafd084ee53ed57672ded03581afdec',
             'candidate': 'e339b80aedae961389dcd1bfcd3dbaab9e244aea9504a3678152bde7b9feae4a'},
    'qbe': {'baseline': '6a97f44864c2e329baa51024f8e6a3ece7653d9d118f54447dd6d7dbc94514aa',
            'candidate': '088b93ef3a7cfa2000e289b10bc6f35e721fcecae0ee40cfc60bbbb58b2de1ad'},
}
KERNEL = 'myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934'


def digest(value):
    return hashlib.sha256(value).hexdigest()


def output(*command):
    return subprocess.check_output(command, text=True)


def parts(text):
    start = text.index('\n@fi55\n')
    original = text.index('\n@oi55\n', start)
    end = text.index('\n@i75\n', original)
    return text[:start], text[start:original], text[original:end]


def normalized(text):
    names = {}
    def replace(match):
        token = match[0]
        if token not in names:
            # Preserve the namespace; only generated numeric suffixes change.
            prefix = re.sub(r'\d+$', '', token)
            names[token] = prefix + str(sum(value.startswith(prefix) for value in names.values()))
        return names[token]
    return re.sub(r'%v\d+|@[A-Za-z_]+\d+', replace, text)


def stored_ssa(directory, label):
    manifest_path = directory / 'manifest.json'
    assert digest(manifest_path.read_bytes()) == MANIFESTS[label]
    manifest = json.loads(manifest_path.read_text())
    assert manifest['identity']['source_revision'] == REVISIONS[label]
    receipt = manifest['identity']['compiler_build_receipt']['receipt']
    assert receipt['compiler_optimize'] == 'Debug' and receipt['status'] == 'complete'
    matches = []
    for path in (directory / 'mycache/modules').glob('*/out/main.manifest.json'):
        for function in json.loads(path.read_text())['functions']:
            if function['name'] == 'main::batch_result' and function['symbol'] == KERNEL:
                matches.append((path, function))
    assert len(matches) == 1
    module, function = matches[0]
    paths = list((directory / 'mycache/frontend/fragments').glob('*/il/' + function['il_digest']))
    assert len(paths) == 1
    data = paths[0].read_bytes()
    return data.decode(), {'manifest': str(manifest_path), 'manifest_sha256': MANIFESTS[label],
                           'module_manifest': str(module), 'module_manifest_sha256': digest(module.read_bytes()),
                           'stored_il': str(paths[0]), 'stored_il_sha256': digest(data),
                           'compiler_sha256': receipt['compiler_sha256'],
                           'compiler_receipt_sha256': manifest['identity']['compiler_build_receipt']['sha256']}


def inspect(path, backend, label):
    expected = PINS[backend][label]
    assert digest(path.read_bytes()) == expected
    symbols = {}
    for line in output('nm', '-S', '--defined-only', str(path)).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2].lower() == 't':
            symbols[fields[3]] = (int(fields[0], 16), int(fields[1], 16))
    start, size = symbols[KERNEL]
    assembly = output('objdump', '-d', '-w', '--no-show-raw-insn', '--disassemble=' + KERNEL, str(path))
    rows = [(int(match[1], 16), match[2]) for line in assembly.splitlines()
            if (match := re.match(r'\s*([0-9a-f]+):\s+(.*)', line))]
    assert rows and all(start <= address < start + size for address, _ in rows)
    section = re.search(r'\]\s+\.text\s+PROGBITS\s+\S+\s+\S+\s+(\S+)', output('readelf', '-SW', str(path)))
    assert digest(path.read_bytes()) == expected  # inspection must never rewrite inputs
    record = {'path': str(path), 'sha256': expected, 'text_bytes': int(section[1], 16),
              'batch_address': hex(start), 'batch_bytes': size, 'assembly_sha256': digest(assembly.encode())}
    return record, rows, assembly


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--assembly-dir', type=Path)
    args = parser.parse_args()
    texts, source_bindings, artifacts, kernels, assemblies = {}, {}, {}, {}, {}
    for label, directory in (('baseline', BASE), ('candidate', AFTER)):
        texts[label], source_bindings[label] = stored_ssa(directory, label)
        for backend in PINS:
            record, rows, assembly = inspect(directory / ('bin/collections-my-' + backend), backend, label)
            artifacts.setdefault(backend, {})[label] = record
            kernels.setdefault(backend, {})[label] = rows
            assemblies[label + '-' + backend + '-batch.asm'] = assembly
    before, after = parts(texts['baseline']), parts(texts['candidate'])
    assert texts['baseline'].count('# mylang-rc-append-range ') == 0
    assert texts['candidate'].count('# mylang-rc-append-range ') == 1
    assert '# mylang-rc-append-range 55\n' in after[0]
    assert after[1].count('myl_qbe_fail_overflow_op') == 0
    assert before[2].count('myl_qbe_fail_overflow_op') == after[2].count('myl_qbe_fail_overflow_op') == 4
    assert normalized(before[2]) == normalized(after[2])
    for copy in after[1:]:
        assert copy.count('call $myl_rc_list_append(') == 1
        assert copy.count('call $myl_rc_list_plain_ready(') == 1
        assert copy.count('call $myl_qbe_fail_allocation(') == 1
        assert ' cultl ' in copy and 'storew 0, %rcappend0' in copy
    assert 'call $myl_rc_list_append(' not in before[1]  # old whole-room copy
    fast = [row for row in kernels['llvm']['candidate'] if 0x1034b50 <= row[0] < 0x1034c72]
    fallback = [row for row in kernels['llvm']['candidate'] if 0x1034c83 <= row[0] < 0x1034e01]
    ordinary = [row for row in kernels['llvm']['baseline'] if 0x1034c8c <= row[0] < 0x1034e15]
    def calls(rows, name):
        return [hex(address) for address, text in rows if re.match(r'call\s', text) and '<' + name + '>' in text]
    assert fast and fallback and ordinary
    assert not any(re.match(r'(jo|seto)\s', text) for _, text in fast)
    assert any('add    $0xd,%r9' == text for _, text in fast)
    assert any(text.startswith('cmp    0x8(%rsi),') for _, text in fast)
    assert calls(fast, 'rc_list_insert_at') == ['0x1034c1f']
    assert calls(fast, 'myl_rc_list_plain_ready') == ['0x1034c50']
    assert any(re.match(r'jo\s', text) for _, text in fallback)
    assert any(re.match(r'jo\s', text) for _, text in ordinary)
    assert calls(fallback, 'rc_list_insert_at') == ['0x1034ccc']
    assert calls(fallback, 'myl_rc_list_plain_ready') == ['0x1034dbe']
    report = {'schema': 'mylang-goal110-append-range-binary-v1', 'status': 'pass',
              'source_revisions': REVISIONS, 'source_bindings': source_bindings, 'artifacts': artifacts,
              'stored_ssa_head': 55, 'stored_ssa_only_new_marker': True,
              'fallback_ssa_identical_after_generated_name_normalization': True,
              'fallback_overflow_trap_calls': 4, 'fast_overflow_trap_calls': 0,
              'fast_and_original_each_retain_ordinary_append_query_and_allocation_failure': True,
              'llvm_fast_loop_range': ['0x1034b50', '0x1034c72'], 'llvm_fast_loop_instructions': len(fast),
              'llvm_growth_call': '0x1034c1f', 'llvm_query_call': '0x1034c50',
              'llvm_fast_loop_no_overflow_condition': True, 'llvm_fast_loop_strength_reduced_add13': True,
              'llvm_original_fallback_range': ['0x1034c83', '0x1034e01'],
              'baseline_whole_room_guard_refuses_positive_empty_list_trips': True,
              'limitations': ['Static inspection establishes instruction removal, retained runtime operations and source identity, not speed.',
                              'Complete ELF and LLVM/QBE batch sizes are recorded; other branches may change layout or register allocation.',
                              'The empty-list refusal is a source/SSA capacity fact; no hardware branch tracing was performed.',
                              'Debug hosts and ReleaseFast guests are diagnostic policy, not normal goal confirmation.']}
    if args.assembly_dir:
        args.assembly_dir.mkdir(parents=True, exist_ok=True)
        for name, assembly in assemblies.items():
            with (args.assembly_dir / name).open('x') as target:
                target.write(assembly)
        for label, text in texts.items():
            _, fast, original = parts(text)
            with (args.assembly_dir / (label + '-append-region.ssa')).open('x') as target:
                target.write(fast + original)
    if args.output:
        with args.output.open('x') as target:
            target.write(json.dumps(report, indent=2) + '\n')
    else:
        assert report == json.loads(Path(__file__).with_name('static-binary.json').read_text())
    print('PASS append6910: fast arithmetic checks removed; ordinary growth retained; complete checked fallback unchanged')


if __name__ == '__main__':
    main()
