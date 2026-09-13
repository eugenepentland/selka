#!/usr/bin/env python3
"""Native ordinary wire ABI validates trees and copies direct ABI structures."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from qbe_embed import library_wrapper

HARNESS=r'''
#include "qbe_runtime.h"
#include "native_host.h"
#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <string.h>
void myl_qbe_host_begin(void *ctx) {(void)ctx;}
typedef struct {_Alignas(8) unsigned char bytes[16];} Pair;
typedef struct {_Alignas(8) unsigned char bytes[24];} Triple;
uint64_t entry(void *ctx){(void)ctx;return 42;}
Pair echo_pair(void *ctx,Pair p){(void)ctx;return p;}
Pair echo_variant(void *ctx,Pair p){(void)ctx;return p;}
Triple echo_array(void *ctx,Triple p){(void)ctx;return p;}
uint64_t echo_scalar(void *ctx,uint64_t p){(void)ctx;return p;}
int main(void){
    MylangWireResult result;
    MylangWireNode output[4];memset(output,0x5a,sizeof output);
    MylangWireNode pair[]={{"Pair",0,2},{"i64",(uint64_t)-9,0},{"bool",1,0}};
    assert(mylang_native_call_values_v1("echo_pair",pair,3,output,4,NULL,&result)==0);
    assert(result.node_count==3 && output[1].bits==(uint64_t)-9 && !strcmp(output[2].type,"bool") && output[2].bits==1);
    output[0].bits=99;
    assert(mylang_native_call_values_v1("echo_pair",pair,3,output,2,NULL,&result)==2);
    assert(!strcmp(result.execution.code,"OutputTooSmall") && result.node_count==3 && output[0].bits==99);
    pair[2].bits=2;
    assert(mylang_native_call_values_v1("echo_pair",pair,3,output,4,NULL,&result)==2 && result.node_count==0);
    assert(!strcmp(result.execution.code,"InvalidArgument"));pair[2].bits=1;
    pair[0].children=1;
    assert(mylang_native_call_values_v1("echo_pair",pair,3,output,4,NULL,&result)==2);pair[0].children=2;
    assert(mylang_native_call_values_v1("echo_pair",pair,2,output,4,NULL,&result)==2);
    MylangWireNode variant[]={{"Choice",1,1},{"i64",27,0}};
    assert(mylang_native_call_values_v1("echo_variant",variant,2,output,4,NULL,&result)==0 && result.node_count==2 && output[0].bits==1 && output[1].bits==27);
    variant[0]=(MylangWireNode){"Choice",0,0};
    assert(mylang_native_call_values_v1("echo_variant",variant,1,output,4,NULL,&result)==0 && result.node_count==1);
    variant[0].bits=2;
    assert(mylang_native_call_values_v1("echo_variant",variant,1,output,4,NULL,&result)==2);
    MylangWireNode array[]={{"Triple",0,3},{"i64",1,0},{"i64",2,0},{"i64",3,0}};
    assert(mylang_native_call_values_v1("echo_array",array,4,output,4,NULL,&result)==0 && result.node_count==4 && output[3].bits==3);
    MylangWireNode scalar={"i64",(uint64_t)-1,0};
    assert(mylang_native_call_values_v1("echo_scalar",&scalar,1,output,4,NULL,&result)==0 && result.node_count==1 && output[0].bits==(uint64_t)-1);
    assert(mylang_native_call_values_v1("missing",NULL,0,output,4,NULL,&result)==2 && !strcmp(result.execution.code,"UnknownFunction"));
    assert(mylang_native_call_values_v1("domain",NULL,0,output,4,NULL,&result)==2 && !strcmp(result.execution.code,"UnsupportedSignature"));
    assert(mylang_native_call_values_v1("echo_scalar",NULL,100001,output,4,NULL,&result)==2);
    return 0;
}
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig',default='zig')
    args=parser.parse_args()
    types=[{'name':'i64','kind':'scalar','size':8,'alignment':8},
           {'name':'bool','kind':'scalar','size':1,'alignment':1},
           {'name':'Pair','kind':'record','size':16,'alignment':8,'fields':[{'type':'i64','offset':0},{'type':'bool','offset':8}]},
           {'name':'Choice','kind':'variant','size':16,'alignment':8,'fields':[{'type':None,'offset':8},{'type':'i64','offset':8}]},
           {'name':'Triple','kind':'array','size':24,'alignment':8,'count':3,'stride':8,'fields':[{'type':'i64','offset':0}]}]
    units=[{'symbol':name,'export':{'name':name,'parameters':[ty],'result':ty,'scalar':ty=='i64'}}
           for name,ty in [('echo_pair','Pair'),('echo_variant','Choice'),('echo_array','Triple'),('echo_scalar','i64'),('domain','Domain')]]
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-wire-') as directory:
        directory=Path(directory)
        wrapper,harness,executable=directory/'wrapper.c',directory/'test.c',directory/'test'
        wrapper.write_text(library_wrapper('entry',units,wire_types=types))
        harness.write_text(HARNESS)
        for mode in ('-O0','-O2'):
            subprocess.run([args.zig,'cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-function',mode,
                            '-fsanitize=undefined','-fno-sanitize-recover=all','-I',str(ROOT/'src'),str(wrapper),str(harness),
                            str(ROOT/'src/qbe_runtime.c'),str(ROOT/'src/qbe_stack.c'),str(ROOT/'src/native_heap.c'),'-lm','-o',str(executable)],check=True,timeout=120)
            subprocess.run([executable],check=True,timeout=30)
    print('QBE ordinary native value marshalling passed (O0/O2, UBSan)')


if __name__=='__main__':
    main()
