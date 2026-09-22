#!/usr/bin/env python3
"""Relink unchanged gc-lto guest objects with regenerated/typed host metadata."""
import hashlib, json, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-gap-audit-20260921/host'
RECEIPT = WORK / 'control.qbe-manifest.json'
COMPILER = ROOT / '.tmp/svg-gap-audit-20260921/mylang-audit-compiler'

def run(argv, stdout=None):
    result = subprocess.run([str(x) for x in argv], cwd=ROOT, text=True,
                            stdout=stdout or subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode: raise RuntimeError(f'{argv}\n{result.stdout}\n{result.stderr}')
    return result.stdout or ''
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def once(source, old, new):
    assert source.count(old) == 1, (old, source.count(old))
    return source.replace(old, new)

receipt = json.loads(RECEIPT.read_text())
guests = [Path(x['object']) for x in receipt['functions']]
extras = [x for x in guests[0].parent.glob('*.o') if x not in guests]
# LTO objects are LLVM bitcode and the system nm cannot decode their symbol
# table. The retained symbol strings distinguish the two driver objects.
entry = next(x for x in extras if 'mylang_native_providers_v5' in run(['strings', x]))
original_metadata = next(x for x in extras if 'qbe_host_invoke' in run(['strings', x]))
manifest = WORK / 'typed-manifest.json'
with manifest.open('w') as out:
    run([COMPILER, 'emit-project-qbe', WORK / 'guest/main.my',
         '--drop-debug', '--drop-step-checks', '--drop-frame-checks'], stdout=out)
metadata = WORK / 'typed-metadata.c'
with metadata.open('w') as out:
    run(['zig', 'run', '--dep', 'outputs',
         '-Mroot=experiments/schematic-parity-audit-20260921/metadata.zig',
         '-Moutputs=src/qbe_build_outputs.zig', '--', manifest], stdout=out)
declarations = json.loads(manifest.read_text())['host']['declarations']
indexes = {x['name']: i for i, x in enumerate(declarations)}
assert {'io::byte', 'io::put'} <= indexes.keys()
generated = metadata.read_text()
generated = '#include <stdint.h>\nextern const char *myl_svg_byte_typed(int64_t,int64_t,uint8_t *);\nextern const char *myl_svg_put_typed(uint8_t,int64_t *);\n' + generated
anchor = '    if (!state->work) { qbe_host_error(ctx,"HostWorkLimit"); return; }\n'
fast = f'''    /* Audit ceiling: initialization validated this binding once. Preserve
       call/work/reentry, provider bounds/output errors and typed results. */
    if (declaration_index == {indexes['io::byte']} || declaration_index == {indexes['io::put']}) {{
        if (state->work < 2) {{ qbe_host_error(ctx,"HostWorkLimit"); return; }}
        state->calls++; state->work -= 2; state->invoking=1;
        const char *failure;
        if (declaration_index == {indexes['io::byte']})
            failure=myl_svg_byte_typed(*(const int64_t *)arguments[0],
                *(const int64_t *)arguments[1],(uint8_t *)output);
        else
            failure=myl_svg_put_typed(*(const uint8_t *)arguments[0],(int64_t *)output);
        state->invoking=0;
        if (failure) qbe_host_error(ctx,failure);
        return;
    }}
'''
typed = once(generated, anchor, anchor + fast)

assets = next((WORK / 'control-cache/runtime').iterdir())
cflags = ['zig', 'cc', '-O3', '-flto', '-std=c11', '-fPIC', '-g0',
          '-ffunction-sections', '-fdata-sections', '-I', assets]
provider = WORK / 'typed-provider.o'
run([*cflags, '-c', HERE / 'native_typed.c', '-o', provider])
records = {}
for name, source, provider_source in (
    ('metadata-control', generated, HERE / 'native_control.c'),
    ('typed-host', typed, HERE / 'native_typed.c')):
    cfile, obj, binary = WORK / f'{name}.c', WORK / f'{name}.o', WORK / name
    cfile.write_text(source)
    run([*cflags, '-c', cfile, '-o', obj])
    pobj = provider
    if name == 'metadata-control':
        pobj = WORK / 'typed-control-provider.o'
        run([*cflags, '-c', provider_source, '-o', pobj])
    run(['zig', 'cc', '-O3', '-flto', '-fPIC', '-g0', *guests, obj, entry,
         pobj, receipt['runtime_object'], '-lm', '-Wl,--gc-sections', '-o', binary])
    records[name] = {'binary': str(binary), 'binary_sha256': sha(binary),
                     'metadata_source_sha256': sha(cfile),
                     'provider_source_sha256': sha(provider_source)}
(HERE / 'typed-builds.json').write_text(json.dumps({
    'compiler_sha256': sha(COMPILER), 'receipt_sha256': sha(RECEIPT),
    'guest_object_hashes': {x['name']: sha(x['object']) for x in receipt['functions']},
    'runtime_object_sha256': sha(receipt['runtime_object']),
    'original_metadata_object_sha256': sha(original_metadata),
    'declaration_indexes': indexes, 'arms': records}, indent=2) + '\n')
