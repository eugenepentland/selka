#!/usr/bin/env python3
"""Bind eight guest binaries and compare every allocated/mapped runtime byte."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts

GROUPS = ('compute', 'collections', 'text', 'legacy')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def manifest(path):
    data = path.read_bytes()
    value = json.loads(data)
    holdouts.check_manifest(path, digest(data), value)
    return value, dict(path=str(path.resolve()), sha256=digest(data),
                      source_revision=value['identity']['source_revision'])


def elf(path):
    data = path.read_bytes()
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert header[0][:6] == b'\x7fELF\x02\x01'
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, header[6] + i * header[11])
                for i in range(header[12])]
    names = sections[header[13]]
    strings = data[names[4]:names[4] + names[5]]
    allocated = {}
    for section in sections:
        if not section[2] & 2:
            continue
        name = strings[section[0]:].split(b'\0', 1)[0].decode()
        assert name not in allocated
        content = b'' if section[1] == 8 else data[section[4]:section[4] + section[5]]
        allocated[name] = (section[1:], digest(content))
    segments = [struct.unpack_from('<IIQQQQQQ', data, header[5] + i * header[9])
                for i in range(header[10])]
    return data, header, allocated, segments


def compare(before_path, after_path):
    before, after = elf(before_path), elf(after_path)
    assert before[1][4] == after[1][4], 'runtime entry changed'
    assert before[2] == after[2], 'allocated section metadata/bytes changed'
    assert before[3] == after[3], 'program headers or segment placement changed'
    differences = []
    loads = []
    for segment in before[3]:
        if segment[0] != 1:
            continue
        offset, size = segment[2], segment[5]
        left = before[0][offset:offset + size]
        right = after[0][offset:offset + size]
        assert len(left) == len(right)
        changed = [offset + i for i, pair in enumerate(zip(left, right)) if pair[0] != pair[1]]
        # Only the section-header-table file offset may differ in a mapped
        # nonexecutable ELF header. Executable LOAD bytes are exact.
        assert set(changed) <= set(range(40, 48)), 'mapped runtime bytes changed'
        assert not changed or (offset == 0 and not segment[1] & 1)
        differences.extend(changed)
        loads.append(dict(metadata=segment, before_sha256=digest(left), after_sha256=digest(right)))
    return dict(before_path=str(before_path), after_path=str(after_path),
                before_sha256=digest(before[0]), after_sha256=digest(after[0]),
                entry_address=before[1][4], allocated_sections=before[2],
                program_headers=before[3], loads=loads, mapped_header_only_differences=differences)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate-manifest', type=Path, required=True)
    parser.add_argument('--llvm-control-manifest', type=Path, required=True)
    parser.add_argument('--qbe-control-manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    candidate, candidate_binding = manifest(args.candidate_manifest)
    llvm, llvm_binding = manifest(args.llvm_control_manifest)
    qbe, qbe_binding = manifest(args.qbe_control_manifest)
    assert llvm_binding['source_revision'] == '5e97db47f08f667d97419abafd098df263a2aec3'
    assert qbe_binding['source_revision'] == '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2'
    rows = []
    for group in GROUPS:
        for backend, control in (('llvm', llvm), ('qbe', qbe)):
            name = group + '/my-' + backend
            before = Path(control['identity']['binary_paths'][name])
            after = Path(candidate['identity']['binary_paths'][name])
            row = compare(before, after)
            assert row['before_sha256'] == control['binary_hashes'][name]
            assert row['after_sha256'] == candidate['binary_hashes'][name]
            row.update(group=group, backend=backend)
            rows.append(row)
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  script_sha256=digest(Path(__file__).read_bytes()), rows=rows,
                  candidate=candidate_binding, llvm_control=llvm_binding, qbe_control=qbe_binding,
                  limitations=['Exact allocated section bytes/metadata, program headers and executable LOAD bytes/placement.',
                               'Only nonexecutable ELF e_shoff bytes40..47 may differ; debug/file bytes may differ.',
                               'No new timing or normal integrated goal confirmation.'])
    with args.output.open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS eight guests: LLVM runtime image equals5e; QBE runtime image equalsG4')


if __name__ == '__main__':
    main()
