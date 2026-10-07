#!/usr/bin/env python3
"""Assembly-only Result tag dependency diagnostic; caller must hold build slot."""
import argparse
import fcntl
import hashlib
import json
import random
import re
import struct
import subprocess
from pathlib import Path
from types import SimpleNamespace
import paired_units as paired


def identity(path):
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def text_section(path, symbol=None):
    data = path.read_bytes()
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    if header[0][:6] != b'\x7fELF\x02\x01':
        raise ValueError('expected little-endian ELF64')
    offset, size, count, names = header[6], header[11], header[12], header[13]
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * size) for i in range(count)]
    strings = data[sections[names][4]:sections[names][4] + sections[names][5]]
    for s in sections:
        end = strings.find(b'\0', s[0])
        if strings[s[0]:end] == b'.text':
            result = data[s[4]:s[4] + s[5]]
            if symbol is not None:
                symbols = subprocess.check_output(['nm', '-S', str(path)], text=True)
                line = next(x for x in symbols.splitlines() if x.endswith(' ' + symbol))
                address, extent = [int(x, 16) for x in line.split()[:2]]
                return address, result[address - s[3]:address - s[3] + extent]
            return result
    raise ValueError('missing text section')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attributes', type=Path, required=True)
    parser.add_argument('--actual', type=Path, required=True)
    parser.add_argument('--whole', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--embedded', action='store_true', help='retain LLVM input kind using module assembly')
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(paired.ROOT / 'experiments')
    area.mkdir(exist_ok=False)
    source = json.loads((args.attributes / 'summary.json').read_text())['cases']['result_propagate']
    argv = source['traced_argv']
    flags = argv[:argv.index('-o')]
    entry = next(x for x in argv if x.endswith('/entry.ll'))
    assembly = area / 'original.s'
    paired.run_build([*flags, '-S', '-o', str(assembly), entry], area / 'extract.log')
    llvm_object = area / 'llvm-entry.o'
    paired.run_build([*flags, '-c', '-o', str(llvm_object), entry], area / 'llvm-object.log')
    text = assembly.read_text()
    pattern = re.compile(r'(callq\s+myl_core_err_trace_origin_preserve_most@PLT\n\s*movl\s+\$1, %edx\n\s*)(movb\s+\$1, %al)')
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise ValueError(f'Err-edge tag not unique: {len(matches)}')
    matched = matches[0]
    report = {'production_change': False, 'complete': False, 'embedded_llvm': args.embedded, 'traced_argv': argv, 'entry': identity(Path(entry)),
              'dead_upper_bits_proof': 'After the AL comparison and void append call, LEA writes full RAX from RDX before any caller read. Append saves/restores RAX but does not use it as an input.',
              'matched_context': text[matched.start():matched.end() + 480], 'arms': {}}
    try:
        for arm in ['assembly_baseline', 'partial_nop', 'full_eax']:
            private = area / arm
            private.mkdir()
            replacement = 'movl\t$1, %eax' if arm == 'full_eax' else 'movb\t$1, %al\n\t.byte 0x0f, 0x1f, 0x00'
            body = text if arm == 'assembly_baseline' else text[:matched.start(2)] + replacement + text[matched.end(2):]
            asm = private / 'entry.s'
            obj = private / 'entry.o'
            asm.write_text(body)
            input_path = asm
            if args.embedded:
                escaped = body.replace('\\', '\\5C').replace('"', '\\22').replace('\n', '\\0A')
                input_path = private / 'entry.ll'
                input_path.write_text('source_filename = "row_result_propagate.my"\nmodule asm "' + escaped + '"\n')
            paired.run_build([*flags, '-c', '-o', str(obj), str(input_path)], private / 'assemble.log')
            code = text_section(obj)
            if arm == 'assembly_baseline' and code != text_section(llvm_object):
                raise ValueError('unmodified assembly object text differs from actual LLVM object')
            command = [str(input_path if args.embedded else obj) if x == entry else x for x in argv]
            command[command.index('-o') + 1] = str(private / 'program')
            paired.run_build(command, private / 'link.log')
            native = private / 'program'
            if arm == 'assembly_baseline' and args.embedded:
                if text_section(native, 'main') != text_section(args.actual, 'main'):
                    raise ValueError('embedded assembly native main address or opcodes differ from actual')
            out = subprocess.check_output(['objdump', '-d', '--disassemble=main', str(native)], text=True)
            (private / 'main.asm').write_text(out)
            report['arms'][arm] = {'assembly': identity(asm), 'object': identity(obj), 'binary': identity(native),
                                   'text_bytes': len(code), 'text_sha256': hashlib.sha256(code).hexdigest(), 'link_argv': command}
        if report['arms']['partial_nop']['text_bytes'] != report['arms']['full_eax']['text_bytes']:
            raise ValueError('matched-size arms differ in text length')
        with Path('/run/user/1000/mylang-slots/cpu10.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            report['measurement'] = paired.comparison(SimpleNamespace(rounds=7), 'result_propagate', {
                'whole': args.whole, 'actual': args.actual,
                **{arm: area / arm / 'program' for arm in report['arms']},
            }, random.Random(81924))
        report['complete'] = True
    finally:
        (area / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
