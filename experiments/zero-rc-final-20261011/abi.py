#!/usr/bin/env python3
"""Record the zero-RC C layout and verify absence of legacy RC implementations."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
from measure import digest, save

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    driver = (ROOT / 'src/core/driver.zig').read_text()
    source_decl = driver.split('pub const runtime_source = ', 1)[1].split(';', 1)[0]
    paths = [ROOT / 'src/core' / path for path in re.findall(r'@embedFile\("([^"]+)"\)', source_decl)]
    source = '#define MYL_ZERO_RC 1\n' + '\n'.join(path.read_text() for path in paths)
    file, obj = args.output / 'runtime.c', args.output / 'runtime.o'
    file.write_text(source)
    command = [str(args.zig.resolve()), 'cc', '-std=c11', '-pthread', '-O0', '-Werror=implicit-function-declaration', '-c', str(file), '-o', str(obj)]
    built = subprocess.run(command, capture_output=True, text=True)
    (args.output / 'compile.stderr').write_text(built.stderr)
    assert built.returncode == 0, built.stderr
    symbols = subprocess.run(['nm', str(obj)], capture_output=True, text=True, check=True).stdout
    (args.output / 'symbols.txt').write_text(symbols)
    forbidden = ('count_load', 'count_retain', 'count_release', 'count_is_unique', 'myl_core_retain', 'myl_core_release', 'myl_core_share', 'myl_core_free_block')
    assert not any(name in symbols for name in forbidden)
    preprocessed = subprocess.run([str(args.zig.resolve()), 'cc', '-std=c11', '-E', '-P', str(file)], capture_output=True, text=True, check=True).stdout
    (args.output / 'runtime.i').write_text(preprocessed)
    header = re.search(r'typedef struct \{([^{}]+)\} myl_block;', preprocessed).group(1)
    assert re.findall(r'\b(uint32_t|int64_t)\s+(\w+)\s*;', header) == [('uint32_t', 'kind'), ('int64_t', 'len'), ('int64_t', 'cap'), ('int64_t', 'reserved')]
    result = {'schema': 'zero-rc-abi-proof-v1', 'source_sha256': digest(file), 'object_sha256': digest(obj),
              'preprocessed_sha256': digest(args.output / 'runtime.i'), 'command': command,
              'inputs': {str(path.relative_to(ROOT)): digest(path) for path in paths},
              'header_members': header.strip(), 'kind_offset': 0, 'header_size': 32,
              'layout_evidence': 'C _Static_asserts in the compiled runtime', 'absent_symbols': list(forbidden)}
    save(HERE / 'abi.json', result)
    print(json.dumps(result), flush=True)

if __name__ == '__main__':
    main()
