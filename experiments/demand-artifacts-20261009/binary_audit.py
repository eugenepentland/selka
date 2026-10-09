"""Audit linked ELF programs while allowing runtime worktree paths in DWARF."""
import hashlib
from pathlib import Path
import struct


def read(path):
    data = Path(path).read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01'
    offset = struct.unpack_from('<Q', data, 40)[0]
    count, names_index = struct.unpack_from('<HH', data, 60)
    headers = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * 64) for i in range(count)]
    names_header = headers[names_index]
    names = data[names_header[4]:names_header[4] + names_header[5]]
    sections = {}
    for header in headers:
        name = names[header[0]:].split(b'\0')[0].decode()
        content = b'' if header[1] == 8 else data[header[4]:header[4] + header[5]]
        sections[name] = (header, content)
    return data, sections


def compare(left_path, right_path):
    left, old = read(left_path)
    right, new = read(right_path)
    assert old.keys() == new.keys(), 'linked section sets differ'
    changed = []
    allocated = []
    for name, (header, content) in old.items():
        current, actual = new[name]
        if header[2] & 2:  # SHF_ALLOC: code, literals, tables, data, unwind info.
            assert (header[1:4], header[5], header[8:], content) == (current[1:4], current[5], current[8:], actual), name
            allocated.append(name)
        if content != actual:
            changed.append(name)
    assert all(name.startswith('.debug_') for name in changed), changed
    paths = []
    for name in ('.debug_str', '.debug_line_str'):
        before = set(old.get(name, (None, b''))[1].split(b'\0'))
        after = set(new.get(name, (None, b''))[1].split(b'\0'))
        differences = before ^ after
        assert all(value.endswith(b'/src/core/runtime') for value in differences), differences
        paths.extend(value.decode() for value in sorted(differences))
    assert left == right or paths, 'unexplained debugger metadata change'
    return {'byte_identical': left == right, 'allocated_sections_identical': allocated,
            'different_sections': changed, 'runtime_source_path_differences': paths,
            'sha256': [hashlib.sha256(value).hexdigest() for value in (left, right)]}
