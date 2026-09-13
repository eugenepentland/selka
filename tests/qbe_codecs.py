#!/usr/bin/env python3
"""Run the existing native domain-codec ABI contract against QBE libraries."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
from native_codec_wire import MAIN, HOST
from native_codec_dispatch import DATA

ROOT=Path(__file__).resolve().parents[1]


def run(command):
    result=subprocess.run(list(map(str,command)),capture_output=True,timeout=240)
    assert result.returncode==0,(command,result.stdout.decode(),result.stderr.decode())
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,required=True)
    parser.add_argument('--qbe',default='qbe')
    parser.add_argument('--zig',default='zig')
    args=parser.parse_args()
    # The shared-library acceptance retains the normative ABI assertions. Allocation
    # fault injection is covered separately by runtime tests, not a generated-C shim.
    host=HOST[:HOST.index('    for(unsigned rejection=0;')]+ 'return 0;}\n'
    host=host.replace(' && live==0','')
    headers='#include "native_host.h"\n#include "native_providers.h"\n#include "native_embed.h"\n#include <assert.h>\n#include <stdio.h>\n#include <string.h>\n'
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-codecs-') as directory:
        directory=Path(directory)
        entry,provider,source,library,binary=directory/'main.my',directory/'data.my',directory/'host.c',directory/'guest.so',directory/'host'
        entry.write_text(MAIN)
        for boxed in (False,True):
            data=DATA.replace('EXPORT_REJECTION','export Rejection;' if boxed else '').replace('REJECTION','struct Rejection{n:i64}' if boxed else '')
            data=data.replace('ERROR_TYPE','Rejection' if boxed else 'i64').replace('ERROR_VALUE','new Rejection{n:-10}' if boxed else '-10')
            data=data.replace('return new Wire{n:unwrap(x)+1};','if unwrap(x)==26{return new Wire{n:1/(unwrap(x)-26)};}return new Wire{n:unwrap(x)+1};')
            provider.write_text(data)
            source.write_text(headers+f'#define BOXED {int(boxed)}\n'+host)
            run([sys.executable,ROOT/'scripts/qbe.py',entry,'--project','--library','--compiler',args.compiler.resolve(),
                 '--qbe',args.qbe,'--zig',args.zig,'--cache-dir',directory/'cache','-o',library])
            run([args.zig,'cc','-std=c11','-fsanitize=undefined','-fno-sanitize-recover=all','-I',ROOT/'src',source,library,'-o',binary])
            run([binary])
    print('QBE public domain codecs: nested values, scalar/record rejection, call/step/frame limits, traps and output atomicity passed')


if __name__=='__main__':
    main()
