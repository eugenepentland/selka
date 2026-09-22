#!/usr/bin/env python3
"""Remove private root-record stores from a proven noncollecting arena closure.

Diagnostic only: never use this lowering with a collecting runtime.
The production parser/translator are imported, not modified.
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
BACKEND = REPO / 'experiments/llvm-backend'
sys.path[:0] = [str(BACKEND), str(BACKEND / 'maxperf')]
import qbe_llvm
import unchecked
spec = importlib.util.spec_from_file_location('maxperf_build', BACKEND / 'maxperf/build.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def root_stores(unit, inventory):
    original_strip(unit, inventory)
    instructions = [i for b in unit.function.blocks for i in b.instructions]
    definitions = {}
    for ins in instructions:
        if ins.dest:
            definitions.setdefault(ins.dest.name, []).append(ins)
    roots = set()
    for name, defs in definitions.items():
        if re.fullmatch(r'root\d+', name):
            assert len(defs) == 1 and defs[0].opcode == 'alloc8'
            assert defs[0].args[0].text == '32'
            roots.add(name)
    addresses = set(roots)
    for ins in instructions:
        if ins.opcode == 'add' and unchecked._temp(ins.args[0]) and ins.args[0].name in roots:
            assert ins.args[1].text in ('8', '16', '24')
            assert len(definitions[ins.dest.name]) == 1
            addresses.add(ins.dest.name)
    # In this captured protocol every root-address operand is consumed only by
    # an address calculation or a store. Any new use must be reviewed first.
    for ins in instructions:
        if any(unchecked._temp(a) and a.name in addresses for a in ins.args):
            assert ins.opcode in ('add', 'storel'), (unit.name, ins.opcode)
    removed = 0
    for block in unit.function.blocks:
        keep = []
        for ins in block.instructions:
            if (ins.opcode == 'storel' and unchecked._temp(ins.args[1])
                    and ins.args[1].name in addresses):
                removed += 1
            else:
                keep.append(ins)
        block.instructions = keep
    inventory.add('removed', 'private_root_record_store', removed)


original_strip = unchecked._strip_arena_roots


def main():
    frozen_root = REPO / '.tmp/bench/armsset'
    work = REPO / '.tmp/llvm-parity-audit-20260920/probes'
    manifest = json.loads((frozen_root / 'manifest.json').read_text())
    builds = json.loads((frozen_root / 'maxperf/builds.json').read_text())
    frozen = frozen_root / 'maxperf/whole-o3'
    assert builder.digest(frozen_root / 'manifest.json') == builds['manifest_sha256']
    assert builder.digest(builds['arms']['whole-o3']['path']) == builds['arms']['whole-o3']['sha256']
    assert builder.digest(frozen / 'runtime.a') == builds['arms']['whole-o3']['runtime_sha256']
    for path, expected in builds['common'].items():
        assert builder.digest(path) == expected, path
    funcs = sorted(manifest['functions'], key=lambda f: f['symbol'])
    signatures = {f['symbol']: qbe_llvm.signature_map(qbe_llvm.parse_unit(f['il'], f['name']))
                  for f in funcs}
    report = {'arms': {}, 'inputs': {str(p): builder.digest(p) for p in
              [frozen_root / 'manifest.json', frozen_root / 'maxperf/builds.json',
               frozen / '000.ll', frozen / 'runtime.a', frozen / 'unchecked_runtime.o',
               work / 'width_probe.o', *map(Path, builds['common'])]},
              'translator_hashes': {str(p): builder.digest(p)
              for p in [BACKEND / 'llvm_emit.py', BACKEND / 'qbe_llvm.py',
                        BACKEND / 'runtime_signatures.py', BACKEND / 'amd64_sysv.py',
                        BACKEND / 'maxperf/unchecked.py', BACKEND / 'maxperf/build.py',
                        Path(__file__)]}}
    for variant in ('regenerated', 'root-clean', 'root-width', 'heap-effects'):
        unchecked._strip_arena_roots = (original_strip if variant in
                                        ('regenerated', 'heap-effects') else root_stores)
        modules, inventory = [], {}
        for function in funcs:
            result = unchecked.translate_unit(function['il'],
                unchecked.Options(mode='unchecked', arena_proven=True),
                signatures, function['name'])
            modules.append(result.ir)
            inventory[function['name']] = result.inventory.removed
        ir = builder.merge_modules(modules)
        if variant == 'regenerated':
            assert ir == (frozen / '000.ll').read_text(), 'translator drift: new control required'
        if variant == 'root-width':
            names = {f['name']: f['symbol'] for f in funcs}
            for name in ('scalar_len', 'literal_width', 'int_width'):
                symbol = names['sexpr.printer::' + name]
                ir, count = re.subn(r'^define [^\n]*@' + symbol +
                                   r'\([^\n]*\) [^\n]*\{\n.*?^}',
                                   f'declare i64 @{symbol}(i64, i64)',
                                   ir, flags=re.M | re.S)
                assert count == 1
        if variant == 'heap-effects':
            declaration = 'declare ptr @myl_qbe_heap(ptr)'
            assert ir.count(declaration) == 1
            ir = ir.replace(declaration, declaration + ' memory(none) nounwind willreturn')
        ll = work / (variant + '.ll')
        ll.write_text(ir)
        obj = ll.with_suffix('.o')
        builder.run(['zig', 'cc', '-c', '-O3', '-fPIC', '-g0', ll, '-o', obj])
        binary = work / (variant + '.bin')
        extra = [work / 'width_probe.o'] if variant == 'root-width' else []
        builder.run(['cc', '-O2', '-fPIC', '-no-pie', obj, frozen / 'unchecked_runtime.o', *extra,
                     *builds['common'], frozen / 'runtime.a',
                     *builds['arms']['whole-o3']['wrappers'], '-lm', '-Wl,--gc-sections',
                     '-o', binary])
        report['arms'][variant] = {'path': str(binary), 'sha256': builder.digest(binary),
                                  'ir_sha256': builder.digest(ll), 'inventory': inventory,
                                  'ir_matches_chart': ir == (frozen / '000.ll').read_text()}
        print(variant, 'matches chart IR:', report['arms'][variant]['ir_matches_chart'],
              'root stores removed:', sum(v.get('private_root_record_store', 0)
                                          for v in inventory.values()), flush=True)
    (HERE / 'root-probe-builds.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
