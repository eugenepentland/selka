#!/usr/bin/env python3
"""Read ELF/code bytes and retained guest symbols; never rewrite an input ELF."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before-manifest', type=Path, required=True)
parser.add_argument('--after-manifest', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)


def artifact(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def text_section(path):
    data = path.read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01'
    offset = struct.unpack_from('<Q', data, 40)[0]
    size, count, strings = struct.unpack_from('<HHH', data, 58)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + index * size) for index in range(count)]
    names = sections[strings]
    names = data[names[4]:names[4] + names[5]]
    for section in sections:
        name = names[section[0]:].split(b'\0', 1)[0]
        if name == b'.text':
            return section[3], data[section[4]:section[4] + section[5]]
    raise ValueError('ELF has no .text')


report = {'schema': 'mylang-unique-capture-static-code-v1', 'manifests': {}, 'entries': []}
for label, path in (('before', args.before_manifest), ('after', args.after_manifest)):
    manifest = json.loads(path.read_text())
    report['manifests'][label] = artifact(path)
    report['manifests'][label]['source_revision'] = manifest['identity']['source_revision']
    for key, filename in manifest['identity']['binary_paths'].items():
        if not key.split('/')[1].startswith('my-'):
            continue
        binary = Path(filename)
        assert artifact(binary)['sha256'] == manifest['binary_hashes'][key]
        sidecar_path = Path(filename + '.qbe-manifest.json')
        sidecar = json.loads(sidecar_path.read_text())
        symbol = sidecar['entry']
        nm = subprocess.check_output(['nm', '-S', '--defined-only', str(binary)], text=True)
        match = re.search(r'^([0-9a-f]+) ([0-9a-f]+) \w ' + re.escape(symbol) + r'$', nm, re.M)
        assert match, (filename, symbol)
        address, extent = (int(item, 16) for item in match.groups())
        base, text = text_section(binary)
        start = address - base
        assert 0 <= start < len(text) and start + extent <= len(text)
        entry = {'arm': label, 'name': key, 'binary': artifact(binary), 'sidecar': artifact(sidecar_path),
                 'policy': {key: sidecar[key] for key in ('backend', 'optimization', 'lto', 'thin_lto')},
                 'symbol': symbol, 'address': hex(address), 'bytes': extent,
                 'entry_sha256': hashlib.sha256(text[start:start + extent]).hexdigest(),
                 'text_bytes': len(text), 'text_sha256': hashlib.sha256(text).hexdigest()}
        if key.startswith('legacy/'):
            command = ['objdump', '-d', '--disassemble=' + symbol, str(binary)]
            assembly = subprocess.check_output(command, text=True)
            destination = output / (label + '-' + key.replace('/', '-') + '-entry.asm')
            destination.write_text(assembly)
            entry['assembly'] = artifact(destination)
            entry['assembly_command'] = command
            entry['unique_local_calls'] = len(re.findall(r'\bcall\s+[^\n]*<myl_qbe_rc_unique_local>', assembly))
        report['entries'].append(entry)
report['limits'] = 'Static emitted-code evidence only. Full .text/entry bytes include relocations; unequal hashes alone do not identify causality.'
report['status'] = 'complete'
(output / 'static-code.json').write_text(json.dumps(report, indent=2) + '\n')
for row in report['entries']:
    print(row['arm'], row['name'], 'entry bytes', row['bytes'], 'uniqueness calls', row.get('unique_local_calls', '-'))
