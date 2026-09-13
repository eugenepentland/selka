#!/usr/bin/env python3
"""Sanitize copied native host scalar validation and per-execution limits."""
from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from qbe_host import source

HARNESS = r'''
#include <assert.h>
void myl_qbe_fail(void *context,const char *code) {
    MylQbeContext *ctx=context;if (!ctx->trap) ctx->trap=code;
}
static int malformed;
static const char *callback(void *unused,MylangHostCall *call) {
    (void)unused;
    assert(call->argument_nodes==1 && call->arguments[0].bits==(uint64_t)-7);
    assert(call->capacity==1);
    call->output[0]=(MylangHostNode){"i8",(uint64_t)-128,malformed?1:0};
    call->output_nodes=1;return NULL;
}
int main(void) {
    const char *parameters[]={"i8"};
    MylangHostBinding binding={"test",parameters,1,"i8",32,32,NULL,callback};
    MylangNativeProviders providers={.host={.bindings=&binding,.count=1,.max_calls=1}};
    MylQbeContext context={.providers=&providers};
    int8_t input=-7,output=0;
    const void *arguments[]={&input};
    myl_f_test_host(&context,arguments,&output);
    assert(!context.trap && output==-128);
    myl_f_test_host(&context,arguments,&output);
    assert(context.trap && !strcmp(context.trap,"R_HOST_LIMIT"));
    free(context.host_state);
    context=(MylQbeContext){.providers=&providers};
    malformed=1;
    myl_f_test_host(&context,arguments,&output);
    assert(context.trap && !strcmp(context.trap,"R_HOST_CONTRACT"));
    free(context.host_state);
    context=(MylQbeContext){.providers=&providers};
    binding.name="unknown";
    myl_qbe_host_begin(&context);
    assert(context.trap && !strcmp(context.trap,"HostUnknownFunction"));
    free(context.host_state);
    return 0;
}
'''


def main():
    metadata = {
        'types': [{'name': 'i8', 'kind': 'scalar', 'size': 1, 'alignment': 1, 'bits': 8, 'signed': True, 'count': 0}],
        'declarations': [{'name': 'test', 'symbol': 'myl_f_test', 'parameters': ['i8'], 'result': 'i8', 'effects': 64}],
    }
    compiler = shlex.split(os.environ.get('CC', 'cc'))
    with tempfile.TemporaryDirectory(prefix='mylang-host-runtime-') as directory:
        temp = Path(directory)
        code = temp / 'host.c'
        code.write_text(source(metadata) + HARNESS)
        for mode in ('-O0', '-O2'):
            executable = temp / 'host'
            subprocess.run(compiler + ['-std=c11', '-Wall', '-Wextra', '-Werror', mode,
                           '-fsanitize=address,undefined', '-I', str(ROOT / 'src'),
                           str(code), '-o', str(executable)], check=True)
            subprocess.run([str(executable)], check=True)
    print('QBE copied host runtime: scalar validation and execution budgets pass ASan/UBSan')


if __name__ == '__main__':
    main()
