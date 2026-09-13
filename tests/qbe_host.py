#!/usr/bin/env python3
"""Native QBE copied-host ABI acceptance against established provider fixtures."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

LIBRARY_HARNESS = r'''
#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <string.h>
static const char *echo(void *ctx,MylangHostCall *call) {
    (void)ctx;
    MylangRunResult nested;
    assert(mylang_native_run_v1(NULL,&nested)==2 && !strcmp(nested.code,"Busy"));
    assert(call->capacity>=call->argument_nodes);
    memcpy(call->output,call->arguments,call->argument_nodes*sizeof(*call->output));
    call->output_nodes=call->argument_nodes;
    return NULL;
}
int main(void) {
    static const char *params[]={"Outcome"};
    static const MylangHostBinding binding={"echo",params,1,"Outcome",64,64,NULL,echo};
    MylangNativeProviders providers={.host={.bindings=&binding,.count=1,.max_calls=1}};
    MylangRunOptions options={.providers=&providers};
    MylangRunResult result;
    assert(mylang_native_run_v1(NULL,&result)==2 && !strcmp(result.code,"HostMissingRegistration"));
    for (int i=0;i<5;i++) assert(mylang_native_run_v1(&options,&result)==0 && result.value==42);
    return 0;
}
'''


def run(command, **kwargs):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=120, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-host-') as directory:
        project = Path(directory)
        (project / 'io.my').write_text('module io;export length;export byte;export put;'
            'host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);'
            'host fn put(value:u8)->i64 effects(host);')
        entry = project / 'main.my'
        entry.write_text('module main;import io;fn main()->i64{let size=io::length();let mut i=0;'
                         'while i<size{discard io::put(io::byte(i));i+=1;}return 0;}')
        for mode in ('Debug', 'ReleaseFast'):
            output = project / mode
            common = [sys.executable, ROOT / 'scripts/qbe.py', '--compiler', args.compiler.resolve(),
                      '--qbe', args.qbe, '--zig', args.zig, '--mode', mode, '--cache-dir', project / 'cache']
            built = run([*common, entry, '--project', '--provider', ROOT / 'tests/native_host_provider.c', '-o', output])
            assert built.returncode == 0, built.stderr.decode()
            native = run([output])
            assert native.returncode == 0 and native.stdout == b'0\n' and native.stderr == b'\x00\xffA', native
            for failure, code in ((1, b'HostMissingRegistration'), (2, b'HostCapabilityDenied'),
                                  (3, b'HostSignatureMismatch'), (4, b'R_HOST_CONTRACT'),
                                  (5, b'R_HOST_FAILURE'), (6, b'R_HOST_LIMIT'),
                                  (7, b'R_HOST_LIMIT'), (8, b'R_HOST_LIMIT')):
                native = run([output], env=dict(os.environ, MYLANG_HOST_MODE=str(failure)))
                assert native.returncode != 0 and not native.stdout and code in native.stderr, (failure, native)
            composite = project / (mode + '-composite')
            built = run([*common, ROOT / 'src/native_fixtures/composite.my', '--provider', ROOT / 'tests/native_host_composite.c', '-o', composite])
            assert built.returncode == 0, built.stderr.decode()
            native = run([composite])
            assert native.returncode == 0 and native.stdout == b'42\n', native
            native = run([composite], env=dict(os.environ, MYLANG_HOST_BAD='1'))
            assert native.returncode != 0 and b'R_HOST_CONTRACT' in native.stderr, native
            wide_source = project / 'wide.my'
            parameters = ','.join(f'a{i}:i64' for i in range(2200))
            arguments = ','.join(str(i) for i in range(2200))
            wide_source.write_text(f'host fn wide({parameters})->i64 effects(host);'
                                  f'fn main()->i64{{return wide({arguments});}}')
            wide_provider = project / 'wide.c'
            wide_provider.write_text('#include "native_providers.h"\n'
                'static const char *wide(void *ctx,MylangHostCall *call){(void)ctx;'
                'if(call->argument_nodes!=2200 || !call->capacity)return "HostFailure";'
                'for(unsigned i=0;i<2200;i++)if(call->arguments[i].bits!=i)return "HostFailure";'
                'call->output[0]=(MylangHostNode){"i64",42,0};call->output_nodes=1;return 0;}'
                'static const char *parameters[]={' + ','.join('"i64"' for _ in range(2200)) + '};'
                'static const MylangHostBinding binding={"wide",parameters,2200,"i64",64,64,0,wide};'
                'MylangNativeProviders mylang_native_providers(void){'
                'return (MylangNativeProviders){.host={.bindings=&binding,.count=1}};}')
            wide_output = project / (mode + '-wide')
            built = run([*common, wide_source, '--provider', wide_provider, '-o', wide_output])
            assert built.returncode == 0, built.stderr.decode()
            native = run([wide_output])
            assert native.returncode == 0 and native.stdout == b'42\n', native
            library = project / (mode + '-host.so')
            built = run([*common, ROOT / 'src/native_fixtures/composite.my', '--library', '-o', library])
            assert built.returncode == 0, built.stderr.decode()
            harness = project / 'library.c'
            harness.write_text(LIBRARY_HARNESS)
            check = project / (mode + '-library-check')
            built = run([args.zig, 'cc', '-std=c11', '-I', ROOT / 'src', harness, library, '-o', check])
            assert built.returncode == 0, built.stderr.decode()
            repeated = run([check])
            assert repeated.returncode == 0, repeated.stderr.decode()
    print('QBE host ABI: copied bytes/composite values and 9 failure modes pass in Debug/ReleaseFast')


if __name__ == '__main__':
    main()
