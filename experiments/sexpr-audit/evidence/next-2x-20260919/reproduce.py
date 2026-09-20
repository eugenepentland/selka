#!/usr/bin/env python3
"""Build and measure audit probes in a fresh scratch directory; no source edits."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--zig-reference', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    parser.add_argument('--qbe', type=Path, default=ROOT / 'zig-out/bin/qbe')
    parser.add_argument('--zig', default=shutil.which('zig'))
    parser.add_argument('--work', type=Path, required=True, help='New directory; must not exist')
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    (work / 'bin').mkdir()
    for source, name in [(args.compiler, 'mylang'), (args.qbe, 'qbe'),
                         (args.zig_reference, 'zig-bench')]:
        shutil.copy2(source, work / 'bin' / name)
    (work / 'base').mkdir()
    shutil.copytree(ROOT / 'experiments/sexpr-port/sexpr', work / 'base/sexpr')
    shutil.copy2(ROOT / 'experiments/sexpr-port/main.my', work / 'base/main.my')
    for name in ['a_read', 'b_tokens', 'c_parse', 'e_scan']:
        shutil.copy2(ROOT / f'experiments/sexpr-audit/{name}.my', work / f'base/{name}.my')
    data = args.input.read_bytes()
    (work / 'input.sexp').write_bytes(data)
    (work / 'input8.sexp').write_bytes(data * 8)
    for variant in ['scalar_string', 'no_text']:
        shutil.copytree(work / 'base', work / variant)
        subprocess.run(['patch', '--batch', '-p0', '-i', str(HERE / f'{variant}.patch')],
                       cwd=work / variant, check=True)
    scan = (work / 'base/e_scan.my').read_text()
    scan = scan.replace('module e_scan', 'module scan_once').replace(
        '        if source[index] == 40 or source[index] == 41:',
        '        byte = source[index]\n        if byte == 40 or byte == 41:')
    (work / 'base/scan_once.my').write_text(scan)

    def build(source, name, extra=()):
        command = [str(work / 'bin/mylang'), 'build', str(work / source),
                   '-o', str(work / name), '--mode', 'ReleaseFast', '--keep-symbols',
                   f'--cache-dir={work}/cache', '--zig', args.zig, *extra]
        subprocess.run(command, cwd=ROOT, check=True)

    builds = [('base/main.my', 'census'), ('scalar_string/main.my', 'census_scalar'),
              ('no_text/main.my', 'census_no_text'), ('base/scan_once.my', 'scan_once')]
    builds += [(f'base/{name}.my', name) for name in ['a_read', 'b_tokens', 'c_parse', 'e_scan']]
    for source, name in builds:
        build(source, name)

    result = subprocess.run([str(work / 'bin/mylang'), 'emit-project-qbe',
                             str(work / 'base/main.my'), '--drop-step-checks'],
                            cwd=ROOT, stdout=subprocess.PIPE, check=True)
    (work / 'census-il.json').write_bytes(result.stdout)
    manifest = json.loads(result.stdout)
    original = manifest['runtime_data']
    assert original.count('myl_print_text') == 1, 'Inspect changed runtime metadata first'
    manifest['runtime_data'] = (
        '#include "native_print.h"\n'
        'void audit_bulk_print_text(MylPrint *, const void *, unsigned);\n'
        + original.replace('myl_print_text', 'audit_bulk_print_text'))
    (work / 'bulk-il.json').write_text(json.dumps(manifest))
    subprocess.run([args.zig, 'cc', '-std=c11', '-O2', '-g0', '-fPIC',
                    '-I', str(ROOT / 'src'), '-c', str(HERE / 'bulk_print.c'),
                    '-o', str(work / 'bulk_print.o')], check=True)
    build('base/main.my', 'census_il', [f'--manifest-file={work}/census-il.json'])
    build('base/main.my', 'census_bulk', [f'--manifest-file={work}/bulk-il.json',
                                       '--link', str(work / 'bulk_print.o')])
    hashes = {str(p.relative_to(work)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((work / 'base').rglob('*.my'))}
    (work / 'source-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    for script in ['measure.py', 'profile.py', 'bulk_measure.py']:
        subprocess.run([sys.executable, str(HERE / script), str(work)], check=True)
    print(f'Raw results: {work}')


if __name__ == '__main__':
    main()
