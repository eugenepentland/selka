#!/usr/bin/env python3
"""Exercise generated QBE scalar embedding adapters through native ABI contracts."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from qbe_embed import library_wrapper

HARNESS = r'''
#include "qbe_runtime.h"
#include "native_host.h"
#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <string.h>
void myl_qbe_host_begin(void *ctx) {(void)ctx;}
uint64_t entry(void *ctx) {(void)ctx;return 42;}
uint64_t add(void *ctx,uint64_t a,uint64_t b) {return myl_qbe_int_binary(ctx,0,1,64,a,b);}
uint64_t narrow(void *ctx,uint64_t a) {(void)ctx;return a;}
uint64_t reenter(void *ctx) {
    (void)ctx;
    MylangRunResult out;
    assert(mylang_native_run_v1(NULL,&out)==2 && !strcmp(out.code,"Busy"));
    return 9;
}
int main(void) {
    assert(!strcmp(mylang_native_schema_json_v1(), "{\"schema\":1}"));
    assert(strlen(mylang_native_schema_sha256_v1())==64);
    MylangCallResult out;
    MylangRunResult run;
    assert(mylang_native_run_v1(NULL,&run)==0 && run.value==42);
    MylangScalar args[]={{"i64",2},{"i64",3}};
    assert(mylang_native_call_v1("demo::add",args,2,NULL,&out)==0);
    assert(out.value.bits==5 && !strcmp(out.value.type,"i64"));
    args[0].bits=INT64_MAX;args[1].bits=1;
    assert(mylang_native_call_v1("demo::add",args,2,NULL,&out)==1);
    assert(!strcmp(out.execution.code,"R_OVERFLOW") && out.value.type==NULL);
    args[0]=(MylangScalar){"i8",(uint64_t)-128};
    assert(mylang_native_call_v1("demo::narrow",args,1,NULL,&out)==0);
    assert(out.value.bits==(uint64_t)-128 && !strcmp(out.value.type,"i8"));
    args[0].bits=128;
    assert(mylang_native_call_v1("demo::narrow",args,1,NULL,&out)==2);
    assert(!strcmp(out.execution.code,"InvalidArgument"));
    args[0].bits=0;args[0].type="i64";
    assert(mylang_native_call_v1("demo::narrow",args,1,NULL,&out)==2);
    assert(mylang_native_call_v1("demo::add",args,1,NULL,&out)==2);
    assert(mylang_native_call_v1("demo::add",NULL,2,NULL,&out)==2);
    assert(mylang_native_call_v1(NULL,NULL,0,NULL,&out)==2);
    assert(mylang_native_call_v1("demo::private",NULL,0,NULL,&out)==2);
    assert(!strcmp(out.execution.code,"UnknownFunction"));
    assert(mylang_native_call_v1("demo::aggregate",NULL,0,NULL,&out)==2);
    assert(!strcmp(out.execution.code,"UnsupportedSignature"));
    assert(mylang_native_call_v1("demo::reenter",NULL,0,NULL,&out)==0 && out.value.bits==9);
    assert(mylang_native_run_v1(NULL,&run)==0 && run.value==42);
    return 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    units = []
    for name, params, result in [('add', ['i64', 'i64'], 'i64'), ('narrow', ['i8'], 'i8'),
                                 ('reenter', [], 'i64'), ('aggregate', [], 'Point')]:
        units.append({'symbol': name, 'export': {'name': 'demo::'+name, 'parameters': params, 'result': result}})
    units.append({'symbol': 'private'})
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-embed-') as directory:
        directory = Path(directory)
        wrapper, harness, executable = directory/'wrapper.c', directory/'test.c', directory/'test'
        wrapper.write_text(library_wrapper('entry', units, '{"schema":1}'))
        harness.write_text(HARNESS)
        for optimization in ('-O0', '-O2'):
            command = [args.zig, 'cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', optimization,
                       '-fsanitize=undefined', '-fno-sanitize-recover=all', '-I', str(ROOT/'src'),
                       str(wrapper), str(harness), str(ROOT/'src/qbe_runtime.c'),str(ROOT/'src/qbe_stack.c'),
                       str(ROOT/'src/native_heap.c'), '-lm', '-o', str(executable)]
            subprocess.run(command, check=True, timeout=120)
            subprocess.run([executable], check=True, timeout=30)
    print('QBE scalar embedding validation, traps, recovery and Busy guard passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()
