#!/usr/bin/env python3
"""Build QBE executables with per-function object reuse (Linux x86-64)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

from qbe_embed import library_wrapper
from qbe_host import source as host_source

ROOT = Path(__file__).resolve().parents[1]


def publish(candidate, output):
    """Keep identical executable files; atomically replace only a complete build."""
    if output.is_file() and os.access(output, os.X_OK):
        if candidate.stat().st_size == output.stat().st_size:
            with candidate.open('rb') as fresh, output.open('rb') as old:
                while True:
                    chunk = fresh.read(65536)
                    if chunk != old.read(65536):
                        break
                    if not chunk:
                        return False
    os.replace(candidate, output)
    return True


def digest_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def key_for(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def atomic_bytes(path, contents):
    with tempfile.NamedTemporaryFile(prefix='.pending-', dir=path.parent, delete=False) as stream:
        pending = Path(stream.name)
        try:
            stream.write(contents)
            stream.close()
            os.replace(pending, path)
        finally:
            pending.unlink(missing_ok=True)


def executable(name):
    found = shutil.which(str(name))
    if found is None:
        raise FileNotFoundError(name)
    return Path(found).resolve()


def run(command, cwd=None, env=None):
    subprocess.run([str(arg) for arg in command], check=True, cwd=cwd, env=env)


def cached_object(cache, key, build):
    path = cache / (key + '.o')
    checksum = cache / (key + '.sha256')
    try:
        if path.stat().st_size > 0 and checksum.read_text() == digest_file(path):
            return path, True
    except (OSError, UnicodeError):
        pass
    with tempfile.TemporaryDirectory(prefix='.compile-', dir=cache) as temporary:
        candidate = Path(temporary) / 'unit.o'
        build(Path(temporary), candidate)
        if candidate.stat().st_size == 0:
            raise ValueError('toolchain produced an empty object')
        digest = digest_file(candidate)
        os.replace(candidate, path)
        atomic_bytes(checksum, digest.encode())
    return path, False


def validate_units(value):
    if value.get('version') != 'qbe-units-v1' or value.get('abi') != 'mylang-qbe-native-v3':
        raise ValueError('unsupported QBE unit format or ABI; rebuild compiler and driver together')
    units = value['functions']
    symbols = set()
    for unit in units:
        if not isinstance(unit['name'], str) or not isinstance(unit['il'], str):
            raise ValueError('invalid QBE function unit')
        symbol = unit['symbol']
        if not isinstance(symbol, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', symbol) or symbol in symbols:
            raise ValueError('invalid or duplicate QBE symbol')
        symbols.add(symbol)
    if value['entry'] not in symbols:
        raise ValueError('QBE entry is not defined')
    return sorted(units, key=lambda unit: unit['symbol'])


def metadata_source(units, runtime_data="", host=None):
    if not isinstance(runtime_data, str):
        raise ValueError("invalid native runtime descriptors")
    lines = ['#include "qbe_runtime.h"', runtime_data, host_source(host or {'types': [], 'declarations': []})]
    for unit in units:
        locations = unit.get('locations', [])
        symbol = unit['symbol'] + '_meta'
        lines.append('static const MylQbeLocation ' + symbol + '_locations[] = {')
        for location in locations:
            path = json.dumps(location['path'], ensure_ascii=False)
            line, column = location['line'], location['column']
            if type(line) is not int or type(column) is not int or line < 0 or column < 0:
                raise ValueError('invalid native source location')
            lines.append('{' + path + ',' + str(line) + ',' + str(column) + '},')
        if not locations:
            lines.append('{0,0,0},')
        lines.append('};')
        lines.append('const MylQbeFunction ' + symbol + ' = {' + json.dumps(unit['name'], ensure_ascii=False) +
                     ',' + symbol + '_locations,' + str(len(locations)) + '};')
    return '\n'.join(lines) + '\n'


def entry_wrapper(entry, parameters, provider=False):
    capabilities = {'clock_cap': 'myl_qbe_grant_external(ctx,0)',
                    'random_cap': 'myl_qbe_grant_external(ctx,1)',
                    'environment_cap': 'myl_qbe_grant_external(ctx,2)',
                    'filesystem_cap': 'myl_qbe_grant_resource(ctx,0)',
                    'network_cap': 'myl_qbe_grant_resource(ctx,1)'}
    if not isinstance(parameters, list) or any(t not in capabilities for t in parameters):
        raise ValueError('unsupported native entry capability')
    packed = len(parameters) > 128
    declaration = ', uint64_t *' if packed else ', uint64_t' * len(parameters)
    lines = ['#include "qbe_runtime.h"', '#include "native_providers.h"', '#include <stdlib.h>',
             'extern void myl_qbe_host_begin(void *);',
             'extern uint64_t '+entry+'(void *'+declaration+');',
             'static uint64_t entry_run(void *ctx) {',
             ' myl_qbe_host_begin(ctx); if (myl_qbe_failed(ctx)) return 0;']
    if packed:
        lines.append(' uint64_t *arguments=calloc('+str(len(parameters))+',sizeof *arguments);')
        lines.append(' if (!arguments) {myl_qbe_fail_allocation(ctx);return 0;}')
    for i, ty in enumerate(parameters):
        variable = 'arguments['+str(i)+']' if packed else 'uint64_t arg'+str(i)
        lines.append(' '+variable+'='+capabilities[ty]+';')
    if packed:
        lines.append(' if (myl_qbe_failed(ctx)) {free(arguments);return 0;}')
        lines.append(' uint64_t answer='+entry+'(ctx,arguments);free(arguments);return answer; }')
    else:
        lines.append(' if (myl_qbe_failed(ctx)) return 0; return '+entry+'(ctx'+
                     ''.join(', arg'+str(i) for i in range(len(parameters)))+'); }')
    setup = 'MylangNativeProviders providers=mylang_native_providers();' if provider else ''
    pointer = '&providers' if provider else 'NULL'
    lines.append('int main(int argc,char **argv) { '+setup+
                 ' return mylang_qbe_run_providers(entry_run,argc,argv,'+pointer+'); }')
    return '\n'.join(lines)+'\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('-o', '--output', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=Path('zig-out/bin/mylang'))
    parser.add_argument('--project', action='store_true')
    parser.add_argument('--provider', type=Path, help='trusted C adapter implementing native_providers.h')
    parser.add_argument('--library', action='store_true', help='build a shared library with native run ABI')
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--target', choices=['amd64_sysv'], default='amd64_sysv')
    parser.add_argument('--mode', choices=['Debug', 'ReleaseFast'], default='Debug')
    parser.add_argument('--cache-dir', type=Path, default=Path('.mylang-cache/qbe'))
    parser.add_argument('--report', action='store_true')
    args = parser.parse_args()
    if args.library and args.provider is not None:
        parser.error('--library receives providers through its host API')
    try:
        if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
            raise ValueError('the initial QBE backend requires a Linux x86-64 host')
        zig, qbe, compiler = executable(args.zig), executable(args.qbe), executable(args.compiler.resolve())
        zig_version = subprocess.check_output([str(zig), 'version'], text=True, timeout=30).strip()
        expected = (ROOT / '.zigversion').read_text().strip()
        if zig_version != expected:
            raise ValueError(f'QBE compilation requires Zig {expected}; found {zig_version}')
        start = time.monotonic()
        generated = subprocess.run([str(compiler), 'emit-project-qbe' if args.project else 'emit-qbe',
                                    str(args.source.resolve())], capture_output=True)
        frontend_seconds = time.monotonic() - start
        sys.stderr.buffer.write(generated.stderr)
        if generated.returncode:
            return generated.returncode if generated.returncode in (1, 2) else 2
        value = json.loads(generated.stdout)
        units = validate_units(value)
        native_start = time.monotonic()
        runtime = ROOT / 'src/qbe_runtime.c'
        header = ROOT / 'src/qbe_runtime.h'
        flags = ['-std=c11', '-O0' if args.mode == 'Debug' else '-O2', '-fno-ident', '-fPIC']
        environment = {
            'cache_version': 1, 'abi': value['abi'], 'compiler': digest_file(compiler),
            'qbe': digest_file(qbe), 'zig': digest_file(zig), 'zig_version': zig_version,
            'target': args.target, 'host': platform.machine(), 'flags': flags,
            'driver': digest_file(Path(__file__).resolve()),
            'embed_driver': digest_file(ROOT / 'scripts/qbe_embed.py'),
            'wire_driver': digest_file(ROOT / 'scripts/qbe_wire.py'),
            'host_driver': digest_file(ROOT / 'scripts/qbe_host.py'),
            'host_runtime': digest_file(ROOT / 'src/qbe_host_runtime.c'),
            'wire_runtime': digest_file(ROOT / 'src/qbe_wire_runtime.c'),
            'runtime': digest_file(runtime), 'runtime_header': digest_file(header),
            'support': {name: digest_file(ROOT / 'src' / name) for name in
                        ['native_host.h', 'native_providers.h', 'native_embed.h',
                         'native_heap.h', 'native_heap.c', 'native_collections.h', 'native_collections.c', 'native_text.h', 'native_text.c',
                         'native_dictionary.h', 'native_dictionary.c', 'qbe_stack.c', 'qbe_providers.c', 'qbe_resources.c', 'native_equal.h', 'native_equal.c',
                         'native_bytes.h', 'native_bytes.c', 'qbe_bytes.h', 'qbe_bytes.c']},
        }
        cache = args.cache_dir.resolve()
        cache.mkdir(parents=True, exist_ok=True)
        output = args.output.resolve()
        records, objects = [], []
        compiled = reused = 0
        for unit in units:
            key = key_for({'environment': environment, 'il': unit['il']})

            def build_function(temporary, candidate, il=unit['il']):
                source, assembly = temporary / 'unit.ssa', temporary / 'unit.s'
                source.write_text(il)
                run([qbe, '-t', args.target, '-o', assembly, source])
                run([zig, 'cc', '-c', assembly, '-o', candidate])

            obj, hit = cached_object(cache, key, build_function)
            reused += int(hit)
            compiled += int(not hit)
            objects.append(obj)
            records.append({'name': unit['name'], 'symbol': unit['symbol'], 'key': key,
                            'object': str(obj), 'reused': hit})
        runtime_key = key_for({'environment': environment, 'kind': 'runtime'})
        runtime_obj, runtime_reused = cached_object(cache, runtime_key,
            lambda temporary, candidate: run([zig, 'cc', *flags, '-c', runtime, '-o', candidate]))
        objects.append(runtime_obj)
        for support in ['native_heap', 'native_collections', 'native_text', 'native_dictionary', 'qbe_stack', 'qbe_providers', 'qbe_resources', 'native_equal', 'native_bytes', 'qbe_bytes']:
            support_key = key_for({'environment': environment, 'kind': support})
            support_obj, _ = cached_object(cache, support_key,
                lambda temporary, candidate, support=support: run([zig, 'cc', *flags, '-c', ROOT / 'src' / (support+'.c'), '-o', candidate]))
            objects.append(support_obj)
        metadata = metadata_source(units, value.get("runtime_data", ""), value.get("host"))
        metadata_key = key_for({'environment': environment, 'metadata': metadata})
        def build_metadata(temporary, candidate):
            source = temporary / 'metadata.c'
            source.write_text(metadata)
            run([zig, 'cc', *flags, '-I', ROOT / 'src', '-c', source, '-o', candidate])
        metadata_obj, metadata_reused = cached_object(cache, metadata_key, build_metadata)
        objects.append(metadata_obj)
        if value.get('text_format'):
            format_key = key_for({'environment': environment,
                                  'format': digest_file(ROOT / 'src/native_format.zig')})
            format_obj, _ = cached_object(cache, format_key,
                lambda temporary, candidate: run([zig, 'build-obj', ROOT / 'src/native_format.zig',
                    '-fPIC', '-O', args.mode, '-femit-bin=' + str(candidate)]))
            objects.append(format_obj)
        codegen_seconds = time.monotonic() - native_start
        link_start = time.monotonic()
        with tempfile.TemporaryDirectory(prefix='.mylang-qbe-', dir=output.parent) as directory:
            temporary = Path(directory)
            wrapper, candidate = temporary / 'entry.c', temporary / 'program'
            wrapper.write_text(entry_wrapper(value['entry'], value.get('entry_parameters', []), args.provider is not None))
            if args.library:
                wrapper.write_text(library_wrapper(value['entry'], units, value.get('schema'), value.get('wire_types'), value.get('entry_parameters', []), value.get('codecs')))
            if args.provider is not None:
                adapter = temporary / 'provider.o'
                provider_env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(temporary / 'provider-cache'),
                                    ZIG_LOCAL_CACHE_DIR=str(temporary / 'provider-local-cache'))
                run([zig, 'cc', *flags, '-I', ROOT / 'src', '-c', args.provider.resolve(), '-o', adapter],
                    env=provider_env)
                objects.append(adapter)
            run([zig, 'cc', *flags, *(['-shared'] if args.library else []), '-fdebug-compilation-dir=mylang-qbe',
                 '-ffile-prefix-map=' + str(temporary) + '=mylang-qbe',
                 '-fdebug-prefix-map=' + str(temporary) + '=mylang-qbe',
                 '-I', ROOT / 'src', 'entry.c', *objects, '-lm', '-o', candidate], cwd=temporary)
            manifest = {'version': 'qbe-manifest-v1', 'abi': value['abi'], 'entry': value['entry'],
                        'functions': records, 'runtime_object': str(runtime_obj)}
            # This manifest is descriptive; linking always uses this invocation's exact object set.
            atomic_bytes(output.with_name(output.name + '.qbe-manifest.json'),
                         (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode())
            changed = publish(candidate, output)
        if args.report:
            print(json.dumps({'version': 'qbe-build-v1', 'output': str(output), 'output_changed': changed,
                              'compiled_functions': compiled, 'reused_functions': reused,
                              'runtime_reused': runtime_reused, 'metadata_reused': metadata_reused, 'functions': records,
                              'frontend_seconds': frontend_seconds, 'codegen_seconds': codegen_seconds,
                              'link_seconds': time.monotonic() - link_start,
                              'native_seconds': time.monotonic() - native_start,
                              'target': args.target, 'mode': args.mode, 'zig_version': zig_version,
                              'artifact_kind': 'shared-library' if args.library else 'executable'},
                             separators=(',', ':')))
        return 0
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        print(f'qbe: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
