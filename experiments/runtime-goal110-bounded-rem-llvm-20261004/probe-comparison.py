#!/usr/bin/env python3
"""Check the ELF comparison's allowed metadata change and three refusals."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    helper = HERE / 'compare-executables.py'
    spec = importlib.util.spec_from_file_location('comparison', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    original, header, _, segments = module.elf(args.binary)
    sections = [struct.unpack_from('<IIQQQQIIQQ', original, header[6] + i * header[11])
                for i in range(header[12])]
    text = next(section for section in sections if section[2] & 6 == 6 and section[5])
    loaded = next(i for i, segment in enumerate(segments) if segment[0] == 1)
    results = []
    with tempfile.TemporaryDirectory(prefix='elf-refusal-') as temporary:
        target = Path(temporary) / 'disposable-elf'

        def check(label, modified, passing):
            target.write_bytes(modified)
            try:
                module.compare(args.binary, target)
            except AssertionError:
                assert not passing, label
                results.append(dict(probe=label, result='refused'))
            else:
                assert passing, label
                results.append(dict(probe=label, result='accepted'))

        check('identical', original, True)
        relocated = bytearray(original)
        table = original[header[6]:header[6] + header[11] * header[12]]
        struct.pack_into('<Q', relocated, 40, len(relocated))
        relocated.extend(table)
        check('section_table_relocated_outside_runtime_image', relocated, True)
        instruction = bytearray(original)
        instruction[text[4]] ^= 1
        check('allocated_instruction_changed', instruction, False)
        placement = bytearray(original)
        offset = header[5] + loaded * header[9] + 16
        struct.pack_into('<Q', placement, offset, segments[loaded][3] + 4096)
        check('load_virtual_address_changed', placement, False)
        mapped_header = bytearray(original)
        mapped_header[48] ^= 1
        check('mapped_header_change_outside_e_shoff', mapped_header, False)
    assert args.binary.read_bytes() == original
    result = dict(status='pass', binary=str(args.binary.resolve()),
                  binary_sha256=hashlib.sha256(original).hexdigest(), probes=results,
                  helper_sha256=hashlib.sha256(helper.read_bytes()).hexdigest(),
                  script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    with args.output.open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print('PASS five comparison probes; immutable input verified unchanged')


if __name__ == '__main__':
    main()
