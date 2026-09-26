#!/usr/bin/env python3
"""Run collection lifetime regressions with an explicit Debug compiler install."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NAMES = ['dictionary_range_keys', 'float_nan', 'properties', 'scalable_sorting',
         'stable_sorting', 'text_views', 'rc_temporary_lifetimes', 'rc_read_loans',
         'rc_nested_read_loans', 'collection_read_callbacks', 'rc_owned_values',
         'rc_view_receivers', 'rc_dictionary_views', 'dictionary_views']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    cases, imports, hashes = [], [], {}
    for index, name in enumerate(NAMES):
        source = ROOT / 'tests/lang' / (name + '.my')
        original = source.read_text()
        module = f'edge_{index}'
        text = re.sub(r'^module \w+', 'module ' + module, original, count=1)
        if not text.startswith('module '):
            text = 'module ' + module + '\n' + text
        (work / (module + '.my')).write_text(text)
        imports.append(module)
        hashes[str(source.relative_to(ROOT))] = hashlib.sha256(original.encode()).hexdigest()
        if name == 'properties':
            cases.append(module + '.test_sorting_orders_and_keeps_every_element([])')
        else:
            cases += [module + '.' + case + '()' for case in re.findall(r'public def (test_\w+)\(\)', text)]
    entry = work / 'driver.my'
    entry.write_text('module driver\n' + ''.join('import ' + module + '\n' for module in imports) +
                     '\ndef main() -> int:\n' + ''.join('    assert ' + case + '\n' for case in cases) + '    return 0\n')
    rows = []
    for backend in ['qbe', 'llvm']:
        binary = work / ('regressions-' + backend)
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(entry),
                   '--rc-runtime=stats', '--backend', backend, '--mode', 'ReleaseFast',
                   '--cache-dir=' + str(work / 'cache'), '-o', str(binary)]
        if backend == 'qbe':
            command += ['--qbe=' + str(compiler.parent / 'qbe')]
        else:
            command += ['--llvm-opt', '3', '--lto']
        subprocess.run(command, cwd=ROOT, check=True)
        run = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=300)
        counts = [json.loads(line.split(' ', 1)[1]) for line in run.stderr.splitlines()
                  if line.startswith('MYLANG_RC_COUNTS ')]
        assert run.returncode == 0 and run.stdout == '' and len(counts) == 1, run.stderr
        count = counts[0]
        assert not count['saturated'] and count['heap_allocate'] == count['retire'], count
        assert count['owner_acquire'] + count['heap_allocate'] == count['owner_release'], count
        assert count['hold_acquire'] == count['hold_release'], count
        rows.append(dict(backend=backend, command=command, cases=cases, source_hashes=hashes,
                         compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                         binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                         exit=run.returncode, stdout=run.stdout, stderr=run.stderr, counts=count))
        args.output.write_text(json.dumps(rows, indent=2) + '\n')
        print(backend, len(cases), count, flush=True)


if __name__ == '__main__':
    main()
