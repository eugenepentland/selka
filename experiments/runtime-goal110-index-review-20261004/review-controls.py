#!/usr/bin/env python3
"""Read-only ELF comparison of the index candidate's unchanged control groups."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
BEFORE = ROOT.parent / 'goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/bin'
AFTER = ROOT.parent / 'goal110-index-forward-rf-20261004/.mylang-cache/goal110-index-forward-rf/runner/bin'


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
        content = b'' if section[1] == 8 else data[section[4]:section[4] + section[5]]
        allocated[name] = (section[1:], hashlib.sha256(content).hexdigest())
    segments = [struct.unpack_from('<IIQQQQQQ', data, header[5] + i * header[9])
                for i in range(header[10])]
    return data, header, allocated, segments


def main():
    rows = []
    for group in ('compute', 'collections', 'text'):
        for backend in ('llvm', 'qbe'):
            name = group + '-my-' + backend
            before, after = elf(BEFORE / name), elf(AFTER / name)
            assert before[1][4] == after[1][4]  # Exact runtime entry address.
            assert before[2] == after[2] and before[3] == after[3]
            differences = []
            for segment in before[3]:
                if segment[0] != 1:
                    continue
                offset, size = segment[2], segment[5]
                left = before[0][offset:offset + size]
                right = after[0][offset:offset + size]
                changed = [offset + i for i, pair in enumerate(zip(left, right)) if pair[0] != pair[1]]
                assert len(left) == len(right)
                # Only the section-header-table file offset may differ in
                # the mapped ELF header. No executable LOAD bytes may differ.
                assert set(changed) <= set(range(40, 48))
                assert not changed or (offset == 0 and not segment[1] & 1)
                differences.extend(changed)
            rows.append(dict(binary=name, allocated_sections=len(before[2]),
                             before_sha256=hashlib.sha256(before[0]).hexdigest(),
                             after_sha256=hashlib.sha256(after[0]).hexdigest(),
                             mapped_header_only_differences=differences))
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(), rows=rows,
                  script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  limitations=['Static identity of allocated sections, program headers and executable LOAD bytes; no new timing.',
                               'Mapped ELF section-table offsets differ; debug/file metadata are not runtime performance evidence.',
                               'Prior passing targets remain stale until normal integrated confirmation.'])
    with Path(sys.argv[1]).open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS six unchanged control binaries; allocated sections and executable LOADs identical')


if __name__ == '__main__':
    main()
