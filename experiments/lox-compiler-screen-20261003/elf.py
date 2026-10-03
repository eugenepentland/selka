"""Compare rebuilt compiler guests without confusing debug metadata with code."""
import hashlib
import struct
from pathlib import Path


def read(path):
    data = Path(path).read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01', 'requires ELF64 little-endian'
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    _, kind, machine, version, entry, phoff, shoff, flags, ehsize, phsize, phnum, shsize, shnum, names = header
    assert machine == 62 and phsize == 56 and shsize == 64, 'requires native amd64 ELF'
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shsize) for i in range(shnum)]
    strings = data[sections[names][4]:sections[names][4] + sections[names][5]]
    result = {}
    for section in sections:
        name = strings[section[0]:].split(b'\0', 1)[0].decode()
        assert name not in result
        contents = data[section[4]:section[4] + section[5]] if section[1] != 8 else b''
        result[name] = {'type': section[1], 'flags': section[2], 'address': section[3],
                        'size': section[5], 'alignment': section[8],
                        'sha256': hashlib.sha256(contents).hexdigest()}
    programs = [struct.unpack_from('<IIQQQQQQ', data, phoff + i * phsize) for i in range(phnum)]
    return {'header': [kind, machine, version, entry, flags, ehsize, phsize, phnum],
            'programs': programs, 'sections': result,
            'file_sha256': hashlib.sha256(data).hexdigest()}


def compare(rebuilt, qualified):
    first, second = read(rebuilt), read(qualified)
    assert first['header'] == second['header'], 'ELF entry/header changed'
    assert first['programs'] == second['programs'], 'ELF program layout changed'
    assert set(first['sections']) == set(second['sections']), 'section set changed'
    differences = []
    allocated = {}
    for name, actual in first['sections'].items():
        expected = second['sections'][name]
        if actual['flags'] & 2 or expected['flags'] & 2:
            assert actual == expected, ('allocated section differs', name)
            allocated[name] = actual
        elif actual != expected:
            assert name.startswith('.debug_') or name in {'.symtab', '.strtab', '.shstrtab'}, ('unexpected nonallocated difference', name)
            differences.append(name)
    return {'rebuilt_sha256': first['file_sha256'], 'qualified_sha256': second['file_sha256'],
            'full_file_byte_exact': first['file_sha256'] == second['file_sha256'],
            'allocated_sections_exact': allocated, 'program_layout_exact': True,
            'nonallocated_metadata_differences': differences,
            'scope': 'Reproduction evidence only; performance uses exact qualified ELF bytes.'}
