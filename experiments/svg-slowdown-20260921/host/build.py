#!/usr/bin/env python3
"""Build isolated host-boundary probes from the full-SVG O3 guest objects."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
FULL = ROOT / '.tmp/full-svg-benchmark-20260921'
WORK = ROOT / '.tmp/svg-slowdown-20260921/host'
OUT = Path(__file__).resolve().parent
RECEIPT = FULL / 'mylang-o3.qbe-manifest.json'


def run(argv, stdout=None):
    result = subprocess.run([str(item) for item in argv], cwd=ROOT, text=True,
                            stdout=stdout or subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f'{argv}\n{result.stdout}\n{result.stderr}')
    return result.stdout or ''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def replace_once(source, old, new):
    assert source.count(old) == 1, (old, source.count(old))
    return source.replace(old, new)


def instrument(source, declaration_count):
    source = '#include <stdio.h>\n' + source
    source = replace_once(source, 'static void qbe_host_invoke(',
        f'static unsigned long long probe_calls[{declaration_count}];\n'
        'static void probe_report(void) {\n'
        f'  for (size_t i=0;i<{declaration_count};i++) '
        'fprintf(stderr,"host_calls %s %llu\\n",qbe_host_declarations[i].name,probe_calls[i]);\n'
        '}\nstatic void qbe_host_invoke(')
    return replace_once(source, 'MylQbeContext *ctx=context;\n    myl_qbe_host_begin(ctx);',
        'static int probe_registered;\n'
        '    if (!probe_registered) { atexit(probe_report); probe_registered=1; }\n'
        '    probe_calls[declaration_index]++;\n'
        '    MylQbeContext *ctx=context;\n    myl_qbe_host_begin(ctx);')


def scalar_fast_path(source):
    anchor = '    if (!state->work) { qbe_host_error(ctx,"HostWorkLimit"); return; }\n'
    fast = r'''    /* Diagnostic scalar-only dispatch. Registration/signature/capability
       validation happened in begin; call/work/reentry and result checks remain. */
    int scalar = declaration->count <= 7 && qbe_host_types[declaration->result].kind == 1;
    for (size_t i=0; scalar && i<declaration->count; i++)
        scalar = qbe_host_types[declaration->parameters[i]].kind == 1;
    if (scalar) {
        MylangHostNode nodes[8] = {{0}};
        for (size_t i=0;i<declaration->count;i++) {
            const QbeHostType *type=&qbe_host_types[declaration->parameters[i]];
            nodes[i]=(MylangHostNode){type->name,qbe_host_word(arguments[i],type),0};
        }
        state->calls++; state->work--;
        MylangHostCall call={nodes,declaration->count,nodes+declaration->count,1,0,state->work,0};
        state->invoking=1;
        const char *failure=binding->invoke(binding->context,&call);
        state->invoking=0;
        if (call.exhausted || call.work_remaining>state->work) qbe_host_error(ctx,"HostWorkLimit");
        else {
            state->work=call.work_remaining;
            if (failure) qbe_host_error(ctx,failure);
            else if (call.output_nodes>1) qbe_host_error(ctx,"ValueCountLimit");
            else if (call.output_nodes!=1) qbe_host_error(ctx,"InvalidDataValue");
            else {
                const QbeHostType *type=&qbe_host_types[declaration->result];
                const MylangHostNode *node=&nodes[declaration->count];
                if (!node->type || strcmp(node->type,type->name)) qbe_host_error(ctx,"ValueTypeMismatch");
                else if (node->children || !qbe_host_valid(type,node->bits)) qbe_host_error(ctx,"InvalidDataValue");
                else memcpy(output,&node->bits,type->size);
            }
        }
        return;
    }
'''.replace('{{0}}', '{0}')
    return replace_once(source, anchor, anchor + fast)


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    receipt = json.loads(RECEIPT.read_text())
    guests = [Path(item['object']) for item in receipt['functions']]
    object_dir = guests[0].parent
    extras = [item for item in object_dir.glob('*.o') if item not in guests]
    entry = next(item for item in extras if re.search(r' T main$', run(['nm', item]), re.M))
    original_metadata = next(item for item in extras if ' T myl_qbe_host_begin' in run(['nm', item]))

    manifest = WORK / 'manifest.json'
    with manifest.open('w') as output:
        run([ROOT / 'zig-out/bin/mylang', 'emit-project-qbe',
             'src/schematic/guest/main.my', '--drop-debug', '--drop-step-checks',
             '--drop-frame-checks'], stdout=output)
    metadata = WORK / 'metadata.c'
    with metadata.open('w') as output:
        run(['zig', 'run', '--dep', 'outputs',
             '-Mroot=experiments/schematic-parity-audit-20260921/metadata.zig',
             '-Moutputs=src/qbe_build_outputs.zig', '--', manifest], stdout=output)
    generated = metadata.read_text()
    declarations = len(json.loads(manifest.read_text())['host']['declarations'])

    assets = next((FULL / 'mylang-cache/runtime').iterdir())
    cflags = ['zig', 'cc', '-O3', '-std=c11', '-fPIC', '-g0',
              '-ffunction-sections', '-fdata-sections', '-I', assets]
    provider = WORK / 'provider.o'
    run([*cflags, '-c', ROOT / 'src/schematic/native_schematic.c', '-o', provider])

    variants = {
        'control': generated,
        'counts': instrument(generated, declarations),
        'scalar-fast': scalar_fast_path(generated),
    }
    records = {}
    original_binary = WORK / 'original-control'
    run(['zig', 'cc', '-O3', '-fPIC', '-g0', *guests, original_metadata, entry,
         provider, receipt['runtime_object'], '-lm', '-Wl,--gc-sections', '-o', original_binary])
    records['original-control'] = {
        'path': str(original_binary.relative_to(ROOT)), 'sha256': sha(original_binary),
        'bytes': original_binary.stat().st_size,
    }
    for name, source in variants.items():
        c_path = WORK / f'metadata-{name}.c'
        object_path = WORK / f'metadata-{name}.o'
        binary = WORK / name
        c_path.write_text(source)
        run([*cflags, '-c', c_path, '-o', object_path])
        run(['zig', 'cc', '-O3', '-fPIC', '-g0', *guests, object_path, entry,
             provider, receipt['runtime_object'], '-lm', '-Wl,--gc-sections', '-o', binary])
        records[name] = {'path': str(binary.relative_to(ROOT)), 'sha256': sha(binary),
                         'bytes': binary.stat().st_size}

    provenance = {
        'semantics': {
            'control': 'regenerated production metadata and unchanged O3 guest objects',
            'counts': 'control plus per-declaration counters printed at process exit',
            'scalar-fast': ('diagnostic scalar-only marshaling path; retains initialization, registry/signature/'
                            'capability validation, call/work budgets, no-reentry and scalar result validation; '
                            'falls through to the production generic bridge for non-scalar declarations'),
            'runner_caveat': ('the entry object retained beside these unbounded guest objects rejects --max-steps; '
                              'qualification invokes the probes without an instruction budget, while host call/work '
                              'budgets and ordinary collecting GC remain enabled'),
        },
        'binaries': records,
        'guest_object_count': len(guests),
        'guest_object_hashes': {item['name']: sha(item['object']) for item in receipt['functions']},
        'source_manifest_sha256': sha(manifest),
        'original_receipt_sha256': sha(RECEIPT),
        'runtime_sha256': sha(receipt['runtime_object']),
        'provider_sha256': sha(ROOT / 'src/schematic/native_schematic.c'),
        'production_bridge_sha256': sha(ROOT / 'src/qbe_host_runtime.c'),
        'generated_metadata_sha256': sha(metadata),
        'original_metadata_object_sha256': sha(original_metadata),
        'compiler_sha256': sha(ROOT / 'zig-out/bin/mylang'),
        'zig_version': run(['zig', 'version']).strip(),
    }
    (OUT / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')


if __name__ == '__main__':
    main()
