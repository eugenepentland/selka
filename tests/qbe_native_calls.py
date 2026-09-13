#!/usr/bin/env python3
"""Call exported scalar and aggregate QBE functions through the native library ABI."""
import argparse
import ctypes
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SOURCE='''module main;
export Pair;export Choice;export add;export echo_pair;export echo_array;export echo_choice;export fail;
struct Pair{x:i64,flag:bool}
union Choice{none,value:i64}
fn add(a:i64,b:i64)->i64{return a+b;}
fn echo_pair(p:Pair)->Pair{let mut q=p;q.x=p.x+1;q.flag=!p.flag;return q;}
fn echo_array(a:[3]i64)->[3]i64{return replace(a,1,42);}
fn echo_choice(c:Choice)->Choice{return c;}
fn fail(x:i64)->i64{return 1/x;}
fn hidden(x:i64)->i64{return x;}
fn main()->i64{return 42;}
'''
HOST=r'''
#include "native_host.h"
#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <string.h>
int main(void){
    MylangRunResult run;
    assert(mylang_native_run_v1(NULL,&run)==0 && run.value==42);
    MylangCallResult call;
    MylangScalar args[]={{"i64",7},{"i64",8}};
    assert(mylang_native_call_v1("main::add",args,2,NULL,&call)==0 && call.value.bits==15);
    args[0].bits=0;
    assert(mylang_native_call_v1("main::fail",args,1,NULL,&call)==1 && !strcmp(call.execution.code,"R_DIVISION_BY_ZERO"));
    assert(call.execution.frame_count && !strcmp(call.execution.frames[0].function,"main::fail"));
    assert(mylang_native_call_v1("main::hidden",args,1,NULL,&call)==2 && !strcmp(call.execution.code,"UnknownFunction"));
    assert(mylang_native_call_v1("main::echo_pair",NULL,0,NULL,&call)==2 && !strcmp(call.execution.code,"UnsupportedSignature"));
    MylangWireResult result;
    MylangWireNode output[4],pair[]={{"main::Pair",0,2},{"i64",(uint64_t)-9,0},{"bool",1,0}};
    assert(mylang_native_call_values_v1("main::echo_pair",pair,3,output,4,NULL,&result)==0);
    assert(result.node_count==3 && output[1].bits==(uint64_t)-8 && output[2].bits==0 && pair[1].bits==(uint64_t)-9);
    output[0].bits=99;
    assert(mylang_native_call_values_v1("main::echo_pair",pair,3,output,2,NULL,&result)==2);
    assert(!strcmp(result.execution.code,"OutputTooSmall") && result.node_count==3 && output[0].bits==99);
    pair[2].bits=2;
    assert(mylang_native_call_values_v1("main::echo_pair",pair,3,output,4,NULL,&result)==2 && !strcmp(result.execution.code,"InvalidArgument"));
    MylangWireNode array[]={{"[3]i64",0,3},{"i64",1,0},{"i64",2,0},{"i64",3,0}};
    assert(mylang_native_call_values_v1("main::echo_array",array,4,output,4,NULL,&result)==0 && result.node_count==4 && output[2].bits==42);
    MylangWireNode choice[]={{"main::Choice",1,1},{"i64",(uint64_t)-1,0}};
    assert(mylang_native_call_values_v1("main::echo_choice",choice,2,output,4,NULL,&result)==0 && result.node_count==2 && output[1].bits==(uint64_t)-1);
    choice[0]=(MylangWireNode){"main::Choice",0,0};
    assert(mylang_native_call_values_v1("main::echo_choice",choice,1,output,4,NULL,&result)==0 && result.node_count==1);
    assert(mylang_native_run_v1(NULL,&run)==0 && run.value==42);
    return 0;
}
'''


def run(command):
    result=subprocess.run(list(map(str,command)),capture_output=True,timeout=180)
    assert result.returncode==0,(command,result.stdout.decode(),result.stderr.decode())
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,required=True)
    parser.add_argument('--qbe',default='qbe')
    parser.add_argument('--zig',default='zig')
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-native-calls-') as directory:
        directory=Path(directory)
        source,host,library,binary=directory/'main.my',directory/'host.c',directory/'guest.so',directory/'host'
        parameters=','.join(f'a{i}:i64' for i in range(160))
        many=f'export many;fn many({parameters})->i64{{return '+'+'.join(f'a{i}' for i in range(160))+';}'
        source.write_text(SOURCE+many+'export large;fn large(a:[1024]i64)->[1024]i64{return a;}'+
                          'export packed;fn packed(a:[128]i64,b:[128]i64,c:[128]i64,d:[128]i64,e:[128]i64)->[128]i64{return e;}')
        many_host='MylangScalar scalars[160];MylangWireNode nodes[160],many_output;for(size_t i=0;i<160;++i){scalars[i]=(MylangScalar){"i64",i};nodes[i]=(MylangWireNode){"i64",i,0};}' \
            'assert(mylang_native_call_v1("main::many",scalars,160,NULL,&call)==0 && call.value.bits==12720);' \
            'assert(mylang_native_call_values_v1("main::many",nodes,160,&many_output,1,NULL,&result)==0 && many_output.bits==12720);'
        large_host='MylangWireNode large_input[1025],large_output[1025];large_input[0]=(MylangWireNode){"[1024]i64",0,1024};for(size_t i=1;i<1025;++i)large_input[i]=(MylangWireNode){"i64",i,0};' \
            'assert(mylang_native_call_values_v1("main::large",large_input,1025,large_output,1025,NULL,&result)==0 && result.node_count==1025 && large_output[1024].bits==1024);'
        packed_host='MylangWireNode packed_input[645],packed_output[129];for(size_t a=0;a<5;++a){packed_input[a*129]=(MylangWireNode){"[128]i64",0,128};for(size_t i=1;i<129;++i)packed_input[a*129+i]=(MylangWireNode){"i64",a*128+i,0};}' \
            'assert(mylang_native_call_values_v1("main::packed",packed_input,645,packed_output,129,NULL,&result)==0 && result.node_count==129 && packed_output[128].bits==640);' \
            'assert(mylang_native_call_codecs_v1("main::packed",packed_input,645,packed_output,129,NULL,&codec_result)==0 && codec_result.value.node_count==129 && packed_output[128].bits==640);'
        host.write_text(HOST.replace('    return 0;','MylangCodecResult codec_result;'+many_host+large_host+packed_host+'    return 0;'))
        run([sys.executable,ROOT/'scripts/qbe.py',source,'--project','--library','--compiler',args.compiler.resolve(),
             '--qbe',args.qbe,'--zig',args.zig,'--cache-dir',directory/'cache','-o',library])
        run([args.zig,'cc','-std=c11','-fsanitize=undefined','-fno-sanitize-recover=all','-I',ROOT/'src',host,library,'-o',binary])
        run([binary])
        loaded=ctypes.CDLL(str(library))
        loaded.mylang_native_schema_json_v1.restype=ctypes.c_char_p
        loaded.mylang_native_schema_sha256_v1.restype=ctypes.c_char_p
        schema=loaded.mylang_native_schema_json_v1()
        assert schema and hashlib.sha256(schema).hexdigest().encode()==loaded.mylang_native_schema_sha256_v1()
    print('Actual QBE scalar/record/array/variant native ABI calls, traps, recovery and schema digest passed')


if __name__=='__main__':
    main()
