"""Read-only ELF64 little-endian inspection; never rewrite an input artifact."""
import hashlib
from pathlib import Path
import struct


def read_elf(path):
    data = Path(path).read_bytes()
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert header[0][:6] == b'\x7fELF\x02\x01'
    section_headers = [struct.unpack_from('<IIQQQQIIQQ', data, header[6] + n * header[11])
                       for n in range(header[12])]
    names_header = section_headers[header[13]]
    names = data[names_header[4]:names_header[4] + names_header[5]]
    sections = {}
    for row in section_headers:
        name = names[row[0]:].split(b'\0', 1)[0].decode()
        sections[name] = {'type': row[1], 'flags': row[2], 'address': row[3],
                          'offset': row[4], 'size': row[5], 'alignment': row[8],
                          'data': b'' if row[1] == 8 else data[row[4]:row[4] + row[5]]}
    program_headers = [struct.unpack_from('<IIQQQQQQ', data, header[5] + n * header[9])
                       for n in range(header[10])]
    return {'data': data, 'header': header, 'sections': sections, 'program_headers': program_headers}


def compare(before, after):
    a, b = read_elf(before), read_elf(after)
    allocated_a = {name: row for name, row in a['sections'].items() if row['flags'] & 2}
    allocated_b = {name: row for name, row in b['sections'].items() if row['flags'] & 2}
    sections = []
    for name in sorted(allocated_a.keys() | allocated_b.keys()):
        old, new = allocated_a.get(name), allocated_b.get(name)
        sections.append({'name': name, 'equal': old == new,
                         'before_sha256': hashlib.sha256(old['data']).hexdigest() if old else None,
                         'after_sha256': hashlib.sha256(new['data']).hexdigest() if new else None})
    segments = []
    for index, (old, new) in enumerate(zip(a['program_headers'], b['program_headers'])):
        if old[0] != 1 and new[0] != 1:
            continue
        old_bytes = a['data'][old[2]:old[2] + old[5]]
        new_bytes = b['data'][new[2]:new[2] + new[5]]
        different = [n for n, (x, y) in enumerate(zip(old_bytes, new_bytes)) if x != y]
        segments.append({'index': index, 'before_program_header': old, 'after_program_header': new,
                         'exact_content_equal': old_bytes == new_bytes,
                         'different_byte_offsets': different,
                         'before_sha256': hashlib.sha256(old_bytes).hexdigest(),
                         'after_sha256': hashlib.sha256(new_bytes).hexdigest()})
    return {'before': str(before), 'after': str(after),
            'all_SHF_ALLOC_sections_identical': all(row['equal'] for row in sections),
            'program_headers_identical': a['program_headers'] == b['program_headers'],
            'ELF_header_changed_fields': [{'index': n, 'before': x, 'after': y} for n, (x, y)
                                         in enumerate(zip(a['header'][1:], b['header'][1:]), 1) if x != y],
            'allocated_sections': sections, 'PT_LOAD_segments': segments}
