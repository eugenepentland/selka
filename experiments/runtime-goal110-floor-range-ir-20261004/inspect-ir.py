#!/usr/bin/env python3
"""Bind actual linked bodies and the separate optimized-IR diagnostic."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture(argv):
    result = subprocess.run(argv, text=True, capture_output=True)
    assert result.returncode == 0, (argv, result.stderr)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cache', type=Path)
    args = parser.parse_args()
    cache = args.cache.resolve()
    library = cache / 'floor-range.so'
    optimized = cache / 'floor-range.optimized.ll'
    optimized_text = optimized.read_text()
    nm = capture(['nm', '-S', '--defined-only', str(library)])
    (cache / 'symbols.txt').write_text(nm)
    bodies, functions = [], []
    for line in nm.splitlines():
        fields = line.split()
        if len(fields) != 4 or not fields[3].startswith(('scalar_', 'loop_')):
            continue
        address, size, _, name = fields
        assembly = capture(['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + name, str(library)])
        asm_path = cache / (name + '.asm')
        asm_path.write_text(assembly)
        instruction_lines = re.findall(r'^\s+[0-9a-f]+:\s+(.+)$', assembly, re.M)
        normalized = '\n'.join(re.sub(r'[0-9a-f]+ <[^>]+>', '<target>', instruction)
                               for instruction in instruction_lines) + '\n'
        ir_match = re.search(r'^define [^\n]*@' + re.escape(name) + r'\([^\n]*\).*?^}',
                             optimized_text, re.M | re.S)
        assert ir_match, name
        body = ir_match.group()
        ir_path = cache / (name + '.optimized.ll')
        ir_path.write_text(body + '\n')
        functions.append({'function': name, 'address': '0x' + address,
                          'bytes': int(size, 16), 'instructions': len(instruction_lines),
                          'assembly_sha256': digest(asm_path),
                          'normalized_instruction_sha256': hashlib.sha256(normalized.encode()).hexdigest(),
                          'optimized_ir_sha256': digest(ir_path),
                          'optimized_srem': len(re.findall(r' = srem ', body)),
                          'optimized_urem': len(re.findall(r' = urem ', body)),
                          'optimized_overflow_intrinsics': body.count('@llvm.sadd.with.overflow.i64'),
                          'optimized_assume_calls': body.count('@llvm.assume'),
                          'assembly_overflow_branches': sum(bool(re.match(r'jo\s', x)) for x in instruction_lines)})
        bodies.append((asm_path, ir_path))
    assert len(functions) == 56
    tools = {}
    for tool, flags in (('zig', ['version']), ('objdump', ['--version']), ('nm', ['--version'])):
        binary = Path(shutil.which(tool)).resolve()
        tools[tool] = {'path': str(binary), 'sha256': digest(binary),
                       'version': capture([str(binary)] + flags).splitlines()[0]}
    document = {'status': 'bound', 'created_utc': datetime.now(timezone.utc).isoformat(),
                'tools': tools, 'library_sha256': digest(library),
                'input_ir_sha256': digest(cache / 'floor-range.ll'),
                'optimized_ir_sha256': digest(optimized), 'functions': functions,
                'limitations': ['OptimizedIR is a separate zig cc O3 diagnostic (driver emitsO2); linked ELF usesfullLTO O3.',
                                'Standalone helpers establish isolated legality/codegen, not actual guest performance.',
                                'Onlypositive literal divisor context modeled; checkedoverflow returned status is an isolated protocol.']}
    (cache / 'static.json').write_text(json.dumps(document, indent=2) + '\n')
    for row in functions:
        if row['function'].endswith('d1000000007'):
            print(row['function'], 'bytes', row['bytes'], 'instructions', row['instructions'],
                  'srem', row['optimized_srem'], 'urem', row['optimized_urem'],
                  'overflow', row['assembly_overflow_branches'])


if __name__ == '__main__':
    main()
