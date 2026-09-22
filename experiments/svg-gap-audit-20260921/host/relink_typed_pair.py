#!/usr/bin/env python3
"""Relink an existing seven-call SVG guest as matched generic/typed host arms.

This consumes the receipt's guest objects and the caller-supplied emitted
manifest verbatim. It does not invoke mylang or regenerate guest code.
"""
import argparse, hashlib, json, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
KNOWN = {
    'io::circuit_input', 'io::pinout_input', 'io::interface_input',
    'io::length', 'io::byte', 'io::put', 'io::issue',
}

def run(argv, stdout=None):
    result = subprocess.run([str(x) for x in argv], cwd=ROOT, text=True,
                            stdout=stdout or subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f'{argv}\n{result.stdout}\n{result.stderr}')
    return result.stdout or ''

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def replace_once(source, old, new):
    assert source.count(old) == 1, (old, source.count(old))
    return source.replace(old, new)

def locate_assets(receipt, guests):
    # object = CACHE/objects/target/key.o; copied runtime headers are below
    # CACHE/runtime/HASH/. All entries for one build have identical contents.
    cache = guests[0].parents[2]
    candidates = sorted((cache / 'runtime').glob('*'))
    if not candidates:
        raise RuntimeError(f'cannot locate copied runtime headers below {cache}')
    return candidates[0]

def typed_metadata(generated, indexes):
    generated = (
        '#include <stdint.h>\n'
        'extern const char *myl_svg_byte_typed(int64_t,int64_t,uint8_t *);\n'
        'extern const char *myl_svg_put_typed(uint8_t,int64_t *);\n' + generated
    )
    anchor = '    if (!state->work) { qbe_host_error(ctx,"HostWorkLimit"); return; }\n'
    byte, put = indexes['io::byte'], indexes['io::put']
    fast = f'''    /* Audit ceiling: begin validated registry/signature/capability.
       Keep call/work/reentry, provider bounds/output errors and typed results. */
    if (declaration_index == {byte} || declaration_index == {put}) {{
        if (state->work < 2) {{ qbe_host_error(ctx,"HostWorkLimit"); return; }}
        state->calls++; state->work -= 2; state->invoking=1;
        const char *failure;
        if (declaration_index == {byte})
            failure=myl_svg_byte_typed(*(const int64_t *)arguments[0],
                *(const int64_t *)arguments[1],(uint8_t *)output);
        else
            failure=myl_svg_put_typed(*(const uint8_t *)arguments[0],
                (int64_t *)output);
        state->invoking=0;
        if (failure) qbe_host_error(ctx,failure);
        return;
    }}
'''
    return generated, replace_once(generated, anchor, anchor + fast)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--receipt', required=True, type=Path,
                        help='already-built .qbe-manifest.json receipt')
    parser.add_argument('--manifest', required=True, type=Path,
                        help='exact emit-project-qbe JSON used for metadata')
    parser.add_argument('--prefix', required=True, type=Path,
                        help='output prefix; creates PREFIX-{metadata-control,typed-host}')
    parser.add_argument('--assets', type=Path,
                        help='copied runtime header directory (normally inferred)')
    args = parser.parse_args()
    receipt_path, manifest_path = args.receipt.resolve(), args.manifest.resolve()
    receipt = json.loads(receipt_path.read_text())
    manifest = json.loads(manifest_path.read_text())
    declarations = manifest['host']['declarations']
    indexes = {item['name']: i for i, item in enumerate(declarations)}
    if set(indexes) != KNOWN or len(declarations) != len(KNOWN):
        raise RuntimeError(f'expected exactly the seven schematic declarations, got {list(indexes)}')

    guests = [Path(item['object']).resolve() for item in receipt['functions']]
    if not guests or any(not path.is_file() for path in guests):
        raise RuntimeError('receipt guest object is missing')
    object_dir = guests[0].parent
    if any(path.parent != object_dir for path in guests):
        raise RuntimeError('guest objects do not share one retained object directory')
    extras = [path for path in object_dir.glob('*.o') if path not in guests]
    entry = next((path for path in extras
                  if 'mylang_native_providers_v5' in run(['strings', path])), None)
    original_metadata = next((path for path in extras
                              if 'qbe_host_invoke' in run(['strings', path])), None)
    if entry is None or original_metadata is None:
        raise RuntimeError('could not identify retained entry/metadata bitcode objects')
    runtime = Path(receipt['runtime_object']).resolve()
    assets = args.assets.resolve() if args.assets else locate_assets(receipt, guests)

    prefix = args.prefix.resolve()
    prefix.parent.mkdir(parents=True, exist_ok=True)
    generated_path = Path(str(prefix) + '-metadata-generated.c')
    with generated_path.open('w') as output:
        run(['zig', 'run', '--dep', 'outputs',
             '-Mroot=experiments/schematic-parity-audit-20260921/metadata.zig',
             '-Moutputs=src/qbe_build_outputs.zig', '--', manifest_path], stdout=output)
    control_source, typed_source = typed_metadata(generated_path.read_text(), indexes)

    lto = bool(receipt.get('lto'))
    lto_flags = ['-flto'] if lto else []
    cflags = ['zig', 'cc', '-O3', *lto_flags, '-std=c11', '-fPIC', '-g0',
              '-ffunction-sections', '-fdata-sections', '-I', assets]
    link_flags = ['zig', 'cc', '-O3', *lto_flags, '-fPIC', '-g0']
    records = {}
    for name, source, provider_source in (
        ('metadata-control', control_source, HERE / 'native_control.c'),
        ('typed-host', typed_source, HERE / 'native_typed.c')):
        stem = Path(str(prefix) + '-' + name)
        source_path, metadata_object = Path(str(stem) + '.c'), Path(str(stem) + '.o')
        provider_object = Path(str(stem) + '-provider.o')
        source_path.write_text(source)
        run([*cflags, '-c', source_path, '-o', metadata_object])
        run([*cflags, '-c', provider_source, '-o', provider_object])
        run([*link_flags, *guests, metadata_object, entry, provider_object,
             runtime, '-lm', '-Wl,--gc-sections', '-o', stem])
        records[name] = {
            'binary': str(stem), 'binary_sha256': sha(stem),
            'metadata_source': str(source_path),
            'metadata_source_sha256': sha(source_path),
            'metadata_object_sha256': sha(metadata_object),
            'provider_source': str(provider_source),
            'provider_source_sha256': sha(provider_source),
            'provider_object_sha256': sha(provider_object),
        }
    evidence = {
        'receipt': str(receipt_path), 'receipt_sha256': sha(receipt_path),
        'exact_manifest': str(manifest_path), 'exact_manifest_sha256': sha(manifest_path),
        'lto': lto, 'assets': str(assets), 'declaration_indexes': indexes,
        'guest_object_count': len(guests),
        'guest_object_hashes': {item['name']: sha(item['object']) for item in receipt['functions']},
        'runtime_object': str(runtime), 'runtime_object_sha256': sha(runtime),
        'entry_object': str(entry), 'entry_object_sha256': sha(entry),
        'original_metadata_object': str(original_metadata),
        'original_metadata_object_sha256': sha(original_metadata),
        'arms': records,
    }
    Path(str(prefix) + '-host-relink.json').write_text(json.dumps(evidence, indent=2) + '\n')

if __name__ == '__main__':
    main()
