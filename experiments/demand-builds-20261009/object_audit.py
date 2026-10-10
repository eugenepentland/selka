"""Compare ELF code, literals, relocations and debugger/trap metadata."""
from collections import Counter
import hashlib
from pathlib import Path
import struct


def digest(data):
    return hashlib.sha256(data).hexdigest()


class Object:
    def __init__(self, path):
        self.path = Path(path)
        self.bytes = self.path.read_bytes()
        data = self.bytes
        assert data[:6] == b'\x7fELF\x02\x01', 'expected ELF64 little-endian object'
        offset = struct.unpack_from('<Q', data, 40)[0]
        count, names_index = struct.unpack_from('<HH', data, 60)
        headers = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * 64) for i in range(count)]
        names_header = headers[names_index]
        names = data[names_header[4]:names_header[4] + names_header[5]]
        self.names = [names[h[0]:].split(b'\0')[0].decode() for h in headers]
        self.sections = {name: data[h[4]:h[4] + h[5]] for name, h in zip(self.names, headers)}
        self.symbols = list(struct.iter_unpack('<IBBHQQ', self.sections['.symtab']))
        strings = self.sections['.strtab']
        self.symbol_names = [strings[s[0]:].split(b'\0')[0].decode() for s in self.symbols]
        self.exports = tuple(sorted(name for name, s in zip(self.symbol_names, self.symbols)
                                    if s[1] >> 4 == 1 and s[1] & 15 == 2 and s[3] != 0))
        self.literals = []
        rodata = self.sections.get('.rodata', b'')
        start = 0
        while True:
            start = rodata.find(bytes.fromhex('ffffffff01070000'), start)
            if start < 0:
                break
            length = struct.unpack_from('<Q', rodata, start + 8)[0]
            if start + 32 + length <= len(rodata):
                self.literals.append((start, rodata[start:start + 32 + length]))
            start += 1

    def target(self, index, addend, kind):
        symbol = self.symbols[index]
        section = self.names[symbol[3]] if symbol[3] < len(self.names) else str(symbol[3])
        offset = symbol[4] + addend + (4 if kind == 2 else 0)
        if section == '.rodata':
            for start, value in self.literals:
                if start <= offset < start + max(32, len(value)):
                    return section, digest(value), offset - start
            last = max((start + len(value) for start, value in self.literals), default=0)
            if offset >= last:
                return section, 'tail:' + digest(self.sections[section][offset:]), 0
        return self.symbol_names[index], section, offset

    def relocations(self, section):
        return [(offset, info & 0xffffffff, self.target(info >> 32, addend, info & 0xffffffff))
                for offset, info, addend in struct.iter_unpack('<QQq', self.sections.get('.rela' + section, b''))]


def compare(left_paths, right_paths):
    left = [Object(p) for p in left_paths]
    right = [Object(p) for p in right_paths]
    wanted = {obj.exports: obj for obj in left}
    actual = {obj.exports: obj for obj in right}
    assert len(wanted) == len(left) and len(actual) == len(right), 'ambiguous exported symbols'
    assert wanted.keys() == actual.keys(), 'changed native unit sets differ'
    rows = []
    for symbols, old in wanted.items():
        new = actual[symbols]
        checks = {'text': old.sections.get('.text') == new.sections.get('.text'),
                  'literal_values': Counter(v for _, v in old.literals) == Counter(v for _, v in new.literals),
                  'literal_references': old.relocations('.text') == new.relocations('.text')}
        for section in ('.debug_line', '.debug_info', '.data.rel.ro', '.eh_frame'):
            checks[section] = (old.sections.get(section) == new.sections.get(section)
                               and old.relocations(section) == new.relocations(section))
        different = [name for name in sorted(set(old.sections) | set(new.sections))
                     if old.sections.get(name) != new.sections.get(name)]
        checks['only_literal_pool_layout_differs'] = set(different) <= {'.rodata', '.rela.text'}
        row = {'baseline': str(old.path), 'candidate': str(new.path), 'checks': checks,
               'byte_identical': old.bytes == new.bytes, 'different_sections': different}
        rows.append(row)
        assert all(checks.values()), row
    return rows
