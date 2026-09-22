#!/usr/bin/env python3
"""Diagnostic SVG probes. Changes are confined to a private build directory."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.tmp/schematic-parity-20260921'
sys.path[:0] = [str(ROOT / 'experiments/llvm-backend'),
                str(ROOT / 'experiments/llvm-backend/maxperf')]
import qbe_llvm
from build import merge_modules


def run(command):
    p = subprocess.run(list(map(str, command)), capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f'{command}\n{p.stdout}\n{p.stderr}')
    return p.stdout


def replace(text, before, after):
    assert text.count(before) == 1, before
    return text.replace(before, after)


def stack_nodes(text):
    text = replace(text,
        'MylangHostNode *nodes=calloc(count+capacity?count+capacity:1,sizeof(*nodes));',
        'MylangHostNode local_nodes[8] = {0};\n'
        '    size_t needed=count+capacity?count+capacity:1;\n'
        '    MylangHostNode *nodes=needed<=8 ? local_nodes : calloc(needed,sizeof(*nodes));')
    assert text.count('free(nodes);') == 2
    return text.replace('free(nodes);', 'if (nodes!=local_nodes) free(nodes);')


def prebind(text, count):
    text = replace(text, 'int initialized;\n} QbeHostState;',
                   f'int initialized;\n    const MylangHostBinding *bound[{count}];\n}} QbeHostState;')
    text = replace(text,
        'for (size_t i=0;i<qbe_host_declaration_count;i++) if (!qbe_host_binding(ctx,state,&qbe_host_declarations[i])) return;',
        'for (size_t i=0;i<qbe_host_declaration_count;i++) {\n'
        '        state->bound[i]=qbe_host_binding(ctx,state,&qbe_host_declarations[i]);\n'
        '        if (!state->bound[i]) return;\n    }')
    return replace(text,
        'const MylangHostBinding *binding=qbe_host_binding(ctx,state,declaration);',
        'const MylangHostBinding *binding=state->bound[declaration_index];')


def instrument(text, count):
    text = '#include <stdio.h>\n' + text
    text = replace(text, 'static void qbe_host_invoke(',
        f'static unsigned long long audit_calls[{count}];\n'
        'static void audit_report(void) {\n'
        f'    for (size_t i=0;i<{count};i++) fprintf(stderr,"audit_calls %s %llu\\n",qbe_host_declarations[i].name,audit_calls[i]);\n'
        '}\nstatic void qbe_host_invoke(')
    return replace(text, 'MylQbeContext *ctx=context;\n    myl_qbe_host_begin(ctx);',
        'static int registered;\n    if (!registered) { atexit(audit_report); registered=1; }\n'
        '    audit_calls[declaration_index]++;\n'
        '    MylQbeContext *ctx=context;\n    myl_qbe_host_begin(ctx);')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    manifest = json.loads((WORK / 'manifest.json').read_text())
    receipt = json.loads((WORK / 'unit-o3.qbe-manifest.json').read_text())
    check = json.loads((WORK / 'manifest-check.json').read_text())
    first_keys = {f['name']: f['key'] for f in receipt['functions']}
    check_keys = {f['name']: f['key'] for f in check['functions']}
    assert first_keys == check_keys, 'whole-module manifest must reproduce every baseline object key'
    (Path(__file__).parent / 'manifest-check.json').write_text(json.dumps({
        'compiled_functions': check['compiled_functions'], 'reused_functions': check['reused_functions'],
        'all_keys_equal': True}, indent=2)+'\n')
    guests = [Path(f['object']) for f in receipt['functions']]
    assert {f['symbol'] for f in manifest['functions']} == {f['symbol'] for f in receipt['functions']}
    extras = [p for p in guests[0].parent.glob('*.o') if p not in guests]
    entry = next(p for p in extras if re.search(r' T main$', run(['nm', p]), re.M))
    metadata = next(p for p in extras if ' T myl_qbe_host_begin' in run(['nm', p]))
    assets = next((WORK / 'cache-o3/runtime').glob('*'))
    cflags = ['zig', 'cc', '-O2', '-std=c11', '-fPIC', '-g0', '-ffunction-sections', '-fdata-sections', '-I', assets]
    provider = WORK / 'provider.o'
    run([*cflags, '-c', ROOT / 'src/schematic/native_schematic.c', '-o', provider])
    original = (WORK / 'metadata.c').read_text()
    assert (assets / 'qbe_host_runtime.c').read_text() in original
    # Keep the original generated metadata as a separate control for the generator.
    count = len(manifest['host']['declarations'])
    variants = {'regenerated': original, 'stack': stack_nodes(original),
                'prebind': prebind(original, count),
                'both': prebind(stack_nodes(original), count),
                'counts': instrument(original, count)}
    outputs = {}
    common = [entry, provider, receipt['runtime_object']]

    def link(name, objects, meta):
        binary = WORK / name
        run(['zig', 'cc', '-O2', '-fPIC', '-g0', *objects, meta, *common, '-lm', '-Wl,--gc-sections', '-o', binary])
        outputs[name] = {'path': str(binary), 'sha256': sha(binary), 'bytes': binary.stat().st_size}

    link('relinked', guests, metadata)
    for name, source in variants.items():
        c = WORK / f'metadata-{name}.c'
        c.write_text(source)
        obj = c.with_suffix('.o')
        run([*cflags, '-c', c, '-o', obj])
        link(name, guests, obj)
        print('built', name, flush=True)
    # Checked, collecting whole-guest O3: retain roots, traps and step accounting.
    functions = manifest['functions']
    sigs = {}
    for f in functions:
        unit = qbe_llvm.parse_unit(f['il'], f['name'])
        sigs[unit.name] = qbe_llvm.signature_map(unit)
    ir = merge_modules([qbe_llvm.translate_text(f['il'], f['name'], sigs) for f in functions])
    ll = WORK / 'whole.ll'
    ll.write_text(ir)
    obj = ll.with_suffix('.o')
    run(['zig', 'cc', '-O3', '-fPIC', '-g0', '-c', ll, '-o', obj])
    link('whole-o3', [obj], metadata)
    link('whole-both', [obj], WORK / 'metadata-both.o')
    print('built whole O3 variants', flush=True)
    facts = {'binaries': outputs, 'manifest_sha256': sha(WORK / 'manifest.json'),
             'compiler_sha256': sha(ROOT / 'zig-out/bin/mylang'),
             'runtime': {'path': receipt['runtime_object'], 'sha256': sha(receipt['runtime_object'])},
             'guest_sources': {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / 'src/schematic/guest').glob('*.my'))},
             'inputs': {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / 'experiments/schematic/fixtures').glob('*.sexp'))},
             'bridge_sha256': sha(ROOT / 'src/qbe_host_runtime.c'),
             'metadata_original_sha256': sha(metadata), 'metadata_regenerated_sha256': sha(WORK / 'metadata-regenerated.o'),
             'whole_ir_sha256': sha(ll), 'zig': run(['zig', 'version']).strip(),
             'revision': run(['git', 'rev-parse', 'HEAD']).strip(),
             'working_tree': run(['git', 'status', '--short'])}
    (ROOT / 'experiments/schematic-parity-audit-20260921/builds.json').write_text(json.dumps(facts, indent=2)+'\n')


if __name__ == '__main__':
    main()
