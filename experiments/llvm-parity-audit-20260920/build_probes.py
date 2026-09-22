#!/usr/bin/env python3
"""Isolated linkage/width ablations of the exact chart's whole-O3 guest IR."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command):
    subprocess.run(list(map(str, command)), check=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--builds', required=True)
    p.add_argument('--manifest', required=True)
    p.add_argument('--work', required=True)
    p.add_argument('--receipt', required=True)
    args = p.parse_args()
    work = Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    builds = json.loads(Path(args.builds).read_text())
    manifest = json.loads(Path(args.manifest).read_text())
    arm = builds['arms']['whole-o3']
    original = Path(arm['path'])
    assert digest(original) == arm['sha256']
    frozen = original.parent / 'whole-o3'
    common = list(builds['common'])
    for path, expected in builds['common'].items():
        assert digest(path) == expected, path
    assert digest(frozen / 'runtime.a') == arm['runtime_sha256']
    ir = (frozen / '000.ll').read_text()
    names = {f['name']: f['symbol'] for f in manifest['functions']}
    preserved = {manifest['entry']}
    for obj in [*common, frozen / 'runtime.a', frozen / 'unchecked_runtime.o']:
        undefined = subprocess.run(['nm', '-u', str(obj)], check=True,
                                   capture_output=True, text=True).stdout
        preserved.update(re.findall(r'\bmyl_f_[0-9a-f]+\b', undefined))
    width_names = {name: names['sexpr.printer::' + name]
                   for name in ('scalar_len', 'literal_width', 'int_width')}
    receipt = {'inputs': {str(p): digest(p) for p in
                         [Path(args.builds), Path(args.manifest), frozen / '000.ll',
                          frozen / 'runtime.a', frozen / 'unchecked_runtime.o',
                          HERE / 'width_probe.c', Path(__file__), *map(Path, common)]},
               'original': {'path': str(original), 'sha256': digest(original)},
               'preserved_symbols': sorted(preserved), 'arms': {}}
    width_object = work / 'width_probe.o'
    run(['zig', 'cc', '-std=c11', '-c', '-O3', '-fPIC', '-g0', '-I', frozen / 'runtime',
         '-DAUDIT_SCALAR_NAME=' + width_names['scalar_len'],
         '-DAUDIT_LITERAL_NAME=' + width_names['literal_width'],
         '-DAUDIT_INT_NAME=' + width_names['int_width'],
         HERE / 'width_probe.c', '-o', width_object])
    for variant in ('rebuilt', 'internal', 'width', 'combined'):
        output_ir = ir
        if variant in ('width', 'combined'):
            for symbol in width_names.values():
                output_ir, count = re.subn(r'^define [^\n]*@' + symbol +
                                          r'\([^\n]*\) [^\n]*\{\n.*?^}',
                                          f'declare i64 @{symbol}(i64, i64)',
                                          output_ir, flags=re.M | re.S)
                assert count == 1, (symbol, count)
        internalized = []
        if variant in ('internal', 'combined'):
            def internalize(match):
                if match[2] in preserved:
                    return match[0]
                internalized.append(match[2])
                return 'define internal ' + match[1] + '@' + match[2] + '('
            output_ir = re.sub(r'^define dso_local (.*?)@(\w+)\(', internalize,
                               output_ir, flags=re.M)
        ll = work / (variant + '.ll')
        ll.write_text(output_ir)
        obj = ll.with_suffix('.o')
        run(['zig', 'cc', '-c', '-O3', '-fPIC', '-g0', ll, '-o', obj])
        binary = work / (variant + '.bin')
        extra = [width_object] if variant in ('width', 'combined') else []
        run(['cc', '-O2', '-fPIC', '-no-pie', obj, frozen / 'unchecked_runtime.o',
             *extra, *common, frozen / 'runtime.a', *arm['wrappers'],
             '-lm', '-Wl,--gc-sections', '-o', binary])
        receipt['arms'][variant] = {'path': str(binary), 'sha256': digest(binary),
                                    'ir_sha256': digest(ll),
                                    'internalized_functions': len(internalized)}
        print(variant, receipt['arms'][variant], flush=True)
    Path(args.receipt).write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
