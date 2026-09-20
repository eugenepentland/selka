#!/usr/bin/env python3
"""Build isolated, valid-input maxperf arms from a frozen native-v5 closure."""
import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import qbe_llvm
import unchecked

RUNTIME_UNITS = '''qbe_runtime.c native_heap.c native_collections.c native_text.c
native_dictionary.c qbe_stack.c qbe_providers.c qbe_resources.c native_equal.c
native_bytes.c qbe_bytes.c native_regions.c qbe_arena.c native_print.c qbe_io.c
native_scoped.c qbe_grants.c qbe_files.c native_text_methods.c'''.split()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{command}\n{result.stdout}\n{result.stderr}')


def runtime_archive(assets, units, archive, compact=False):
    runtime_object = archive.with_suffix('.o')
    run(['zig', 'build-obj', '-fPIC', '-lc', '-OReleaseFast', '-I', assets, '-cflags',
         '-std=c11', '-O2', '-g0', '-fno-ident', '-ffunction-sections', '-fdata-sections',
         *(['-DMYL_MAXPERF_ARENA_COMPACT'] if compact else []),
         f'-ffile-prefix-map={assets}=mylang-runtime', f'-fdebug-prefix-map={assets}=mylang-runtime',
         '-fdebug-compilation-dir=mylang-runtime', '--', *units, f'-femit-bin={runtime_object}'])
    archive.unlink(missing_ok=True)
    run(['zig', 'ar', 'rcs', archive, runtime_object])


def merge_modules(modules):
    """One module makes cross-function optimization possible without a new ABI."""
    functions, globals_, declarations, names = [], {}, {}, set()
    for ir in modules:
        match = re.search(r'^define .*?^}', ir, re.M | re.S)
        if not match:
            raise ValueError('expected exactly one definition per emitted unit')
        body = match[0].replace('dllexport ', 'dso_local ')
        # The adapter conservatively marks independent QBE functions noinline.
        # Whole-module arm deliberately permits inlining, preserving other attrs.
        attrs = re.search(r'^attributes #0 = \{ (.*) \}', ir, re.M)
        body = body.replace(' #0 {', ' ' + (attrs[1].replace('noinline', '') if attrs else '') + ' {')
        names.add(re.search(r'@(\w+)\(', body)[1])
        functions.append(body)
        for line in ir.splitlines():
            if line.startswith('@'):
                name = line.split(' = ')[0]
                if name in globals_ and globals_[name] != line:
                    raise ValueError(f'conflicting global: {name}')
                globals_[name] = line
            if line.startswith('declare '):
                name = re.search(r'@(\S+)\(', line)[1]
                if name in declarations and declarations[name] != line:
                    raise ValueError(f'conflicting declaration: {name}')
                declarations[name] = line
    return ('target triple = "x86_64-unknown-linux-gnu"\n' +
            '\n'.join(globals_.values()) + '\n' +
            '\n'.join(d for n, d in declarations.items() if n not in names) +
            '\n' + '\n\n'.join(functions) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--receipt', required=True)
    parser.add_argument('--formatter', required=True)
    parser.add_argument('--runtime-sources', required=True)
    parser.add_argument('--work', required=True)
    parser.add_argument('--arms', default='control,arena,unchecked,whole-o3,compact-o3')
    options = parser.parse_args()
    work = Path(options.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(Path(options.manifest).read_text())
    receipt = json.loads(Path(options.receipt).read_text())
    if manifest['abi'] != 'mylang-qbe-native-v5' or receipt['abi'] != manifest['abi']:
        parser.error('this experiment requires the frozen native-v5 ABI')
    guest_objects = {str(Path(f['object']).resolve()) for f in receipt['functions']}
    cache = Path(next(iter(guest_objects))).parent
    # A compiler build may also publish the number-formatting unit into this
    # directory. It arrives through --formatter, so linking it again here would
    # duplicate myl_native_number_parse; drop it from the arm's common objects.
    def formatting_unit(path):
        symbols = subprocess.run(['nm', '--defined-only', str(path)], capture_output=True, text=True).stdout
        return any(line.split() and line.split()[-1] in ('myl_native_number_parse', 'myl_native_text_scalar')
                   for line in symbols.splitlines())

    extras = sorted(str(x) for x in cache.glob('*.o')
                    if str(x) not in guest_objects and not formatting_unit(x))
    if len(extras) != 2:
        parser.error(f'expected metadata and entry objects; got {extras}')
    common = extras + [str(Path(options.formatter).resolve())]
    funcs = sorted(manifest['functions'], key=lambda f: f['symbol'])
    signatures = {}
    for function in funcs:
        unit = qbe_llvm.parse_unit(function['il'], function['name'])
        signatures[unit.name] = qbe_llvm.signature_map(unit)
    source = Path(options.runtime_sources).resolve()
    source_hashes = {p.name: digest(p) for p in sorted(source.iterdir()) if p.is_file()}
    provenance = {
        'manifest_sha256': digest(options.manifest), 'abi': manifest['abi'],
        'runtime_sources': str(source), 'runtime_source_hashes': source_hashes,
        'common': {x: digest(x) for x in common}, 'arms': {},
    }
    if (work / 'builds.json').exists():
        old = json.loads((work / 'builds.json').read_text())
        for key in ('manifest_sha256', 'common', 'runtime_source_hashes'):
            if old[key] != provenance[key]:
                parser.error(f'work directory belongs to different inputs: {key}')
        provenance['arms'].update(old['arms'])
    for arm in options.arms.split(','):
        if arm not in ('control', 'arena', 'unchecked', 'whole-o3', 'compact-o3'):
            parser.error(f'unknown arm: {arm}')
        started = time.monotonic()
        mode = 'baseline' if arm == 'control' else 'arena' if arm == 'arena' else 'unchecked'
        out = work / arm
        out.mkdir(exist_ok=True)
        assets = out / 'runtime'
        shutil.copytree(source, assets, dirs_exist_ok=True)
        for name in ('arena_heap.c', 'arena_heap.h', 'unchecked_runtime.c', 'heap_stats.c'):
            if (HERE / name).exists():
                shutil.copy2(HERE / name, assets / name)
        runtime_units = [assets / ('arena_heap.c' if unit == 'native_heap.c' and mode != 'baseline' else unit)
                         for unit in RUNTIME_UNITS]
        archive = out / 'runtime.a'
        compact = arm == 'compact-o3'
        runtime_archive(assets, runtime_units, archive, compact)
        modules, inventories = [], {}
        for function in funcs:
            result = unchecked.translate_unit(function['il'],
                unchecked.Options(mode=mode, arena_proven=mode != 'baseline'), signatures, function['name'])
            modules.append(result.ir)
            inventories[function['name']] = asdict(result.inventory)
        if arm in ('whole-o3', 'compact-o3'):
            modules = [merge_modules(modules)]
        objects = []
        opt = '-O3' if arm in ('whole-o3', 'compact-o3') else '-O2'
        for index, ir in enumerate(modules):
            ll = out / f'{index:03}.ll'
            ll.write_text(ir)
            obj = ll.with_suffix('.o')
            run(['zig', 'cc', '-c', opt, '-fPIC', '-g0', ll, '-o', obj])
            objects.append(obj)
        wrappers = []
        if mode == 'unchecked':
            shim = out / 'unchecked_runtime.o'
            run(['zig', 'cc', '-std=c11', '-c', '-O2', '-fPIC', '-g0', '-I', assets,
                 assets / 'unchecked_runtime.c', '-o', shim])
            objects.append(shim)
            names = sorted(set(re.findall(r'\b__wrap_(myl_\w+)\s*\(',
                                          (assets / 'unchecked_runtime.c').read_text())))
            wrappers = [f'-Wl,--wrap={name}' for name in names]
        binary = work / (arm + '.bin')
        # This Zig snapshot's linker rejects --wrap. Use one identical system
        # linker recipe for every arm, including the rebuilt GC control.
        link = ['cc', '-O2', '-fPIC', '-no-pie', *objects, *common, archive, *wrappers,
                '-lm', '-Wl,--gc-sections']
        run([*link, '-o', binary])
        diagnostic = None
        if (assets / 'heap_stats.c').exists():
            stats = out / 'heap_stats.o'
            run(['zig', 'cc', '-c', '-O2', '-I', assets,
                 *(['-DMYL_MAXPERF_STATS_ARENA'] if mode != 'baseline' else []),
                 assets / 'heap_stats.c', '-o', stats])
            diagnostic = work / (arm + '.stats.bin')
            # --wrap cannot intercept the internal call in the merged runtime
            # object. Add one diagnostic-only hook while the Context is alive.
            original = (assets / 'qbe_runtime.c').read_text()
            marker = 'if (!context->trap) result->value = myl_qbe_on_stack(entry,context);'
            if original.count(marker) != 1:
                raise ValueError('diagnostic hook no longer matches the runtime')
            instrumented = assets / 'qbe_runtime_stats.c'
            header = '#include "qbe_runtime.h"'
            if original.count(header) != 1:
                raise ValueError('diagnostic declaration no longer matches the runtime')
            instrumented.write_text(original.replace(header, header + '\n'
                'void myl_maxperf_capture_heap_stats(MylQbeContext *);').replace(
                marker, marker + '\n    myl_maxperf_capture_heap_stats(context);'))
            stats_archive = out / 'runtime-stats.a'
            runtime_archive(assets, [instrumented if p.name == 'qbe_runtime.c' else p
                                    for p in runtime_units], stats_archive, compact)
            stats_link = [stats_archive if p == archive else p for p in link]
            run([*stats_link, stats, '-Wl,--wrap=myl_qbe_on_stack', '-o', diagnostic])
        inventory_path = out / 'inventory.json'
        inventory_path.write_text(json.dumps(inventories, indent=2) + '\n')
        provenance['arms'][arm] = {
            'path': str(binary), 'sha256': digest(binary), 'mode': mode, 'opt': opt,
            'compact_arena': compact,
            'build_seconds': time.monotonic() - started,
            'runtime_sha256': digest(archive), 'stats_binary': str(diagnostic) if diagnostic else None,
            'wrappers': wrappers, 'inventory': str(inventory_path),
            'recipe': {str(p): digest(p) for p in sorted(HERE.iterdir()) if p.suffix in ('.py', '.c', '.h')},
        }
        (work / 'builds.json').write_text(json.dumps(provenance, indent=2) + '\n')
        print(f'{arm}: {binary} ({time.monotonic() - started:.2f}s)', flush=True)


if __name__ == '__main__':
    main()
