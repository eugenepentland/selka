"""Public domain codec ABI validates inputs and stages once-only encoded outputs."""
import argparse
from pathlib import Path
import tempfile
from native_embedding import TRACKER, invoke
from native_codec_dispatch import DATA

MAIN = '''module main;import data;export echo;export Bundle;export Choice;export nested;
struct Bundle{items:[2]data::Positive}
union Choice{none,bundle:Bundle}
fn nested(x:Choice)->Choice{return x;}
fn echo(x:data::Positive)->data::Positive{return x;}
fn main()->i64{return 0;}
'''
HOST = r'''
int main(void) {
    MylangWireNode input[]={{"data::Positive",0,1},{"data::Wire",0,1},{"i64",7,0}};
    MylangWireNode output[8],before[8];memset(before,0xa5,sizeof before);
    MylangCodecOptions options={0};MylangCodecResult result;
    #define CALL() mylang_native_call_codecs_v1("main::echo",input,3,output,8,&options,&result)
    assert(CALL()==0 && live==0);
    assert(result.calls==3 && !result.rejected && !result.domain && result.value.node_count==3);
    assert(!strcmp(output[0].type,"data::Positive") && output[0].children==1 && !output[0].bits);
    assert(!strcmp(output[1].type,"data::Wire") && output[1].children==1 && output[2].bits==15);
    uint64_t steps=result.value.execution.steps;
    MylangWireNode nested[]={
        {"main::Choice",1,1},{"main::Bundle",0,1},{"[2]data::Positive",0,2},
        {"data::Positive",0,1},{"data::Wire",0,1},{"i64",7,0},
        {"data::Positive",0,1},{"data::Wire",0,1},{"i64",8,0}};
    MylangWireNode nested_output[9];
    assert(mylang_native_call_codecs_v1("main::nested",nested,9,nested_output,9,NULL,&result)==0);
    assert(result.calls==5 && result.value.node_count==9 && nested_output[5].bits==15 && nested_output[8].bits==17 && live==0);
    options.max_calls=3;assert(CALL()==0 && result.calls==3 && live==0);
    options.max_calls=2;memcpy(output,before,sizeof output);
    assert(CALL()==2 && !strcmp(result.value.execution.code,"CodecCallLimit") && result.calls==2 && live==0);
    assert(result.domain && !strcmp(result.domain,"data::Positive") && !result.value.node_count && !memcmp(output,before,sizeof output));
    options.max_calls=0;options.run.max_steps=steps-1;
    assert(CALL()==1 && !strcmp(result.value.execution.code,"R_STEP_LIMIT") && live==0);
    options.run.max_steps=0;options.run.max_frames=1;
    assert(CALL()==1 && !strcmp(result.value.execution.code,"R_FRAME_LIMIT") && live==0);
    options.run.max_frames=0;
    memcpy(output,before,sizeof output);
    assert(mylang_native_call_codecs_v1("main::echo",input,3,output,2,NULL,&result)==2);
    assert(!strcmp(result.value.execution.code,"OutputTooSmall") && result.value.node_count==3 && result.calls==3 && live==0);
    assert(!memcmp(output,before,sizeof output));
    input[2].bits=(uint64_t)-1;
    assert(CALL()==2 && result.rejected && result.calls==1 && live==0);
    assert(!strcmp(result.value.execution.code,"DomainCodecRejected") && !strcmp(result.domain,"data::Positive"));
    assert(result.value.node_count==(BOXED?2:1) && output[BOXED?1:0].bits==(uint64_t)-10);
    memcpy(output,before,sizeof output);
    assert(mylang_native_call_codecs_v1("main::echo",input,3,NULL,0,NULL,&result)==2);
    assert(result.rejected && !strcmp(result.value.execution.code,"OutputTooSmall") && result.value.node_count==(BOXED?2:1) && live==0);
    assert(mylang_native_call_codecs_v1("data::Positive.from_wire",input+1,2,output,8,NULL,&result)==0);
    assert(!result.rejected && result.calls==1 && output[0].bits==1 && live==0);
    input[2].bits=99;
    assert(CALL()==1 && !strcmp(result.value.execution.code,"R_DIVISION_BY_ZERO") && result.domain && live==0);
    input[2].bits=13;memcpy(output,before,sizeof output);
    assert(CALL()==1 && !strcmp(result.value.execution.code,"R_DIVISION_BY_ZERO") && result.domain && live==0);
    assert(result.calls==3 && !result.value.node_count && !memcmp(output,before,sizeof output));
    assert(result.value.execution.frame_count==1 && !strcmp(result.value.execution.frames[0].function,"data::Positive.to_wire"));
    input[2].bits=7;
    MylangWireResult ordinary;
    assert(mylang_native_call_values_v1("main::echo",input,3,output,8,NULL,&ordinary)==2);
    assert(!strcmp(ordinary.execution.code,"UnsupportedSignature") && live==0);
    input[0].bits=1;assert(CALL()==2 && !strcmp(result.value.execution.code,"InvalidArgument") && !result.calls && live==0);
    input[0].bits=0;input[0].children=0;assert(CALL()==2 && !result.calls && live==0);input[0].children=1;
    for(unsigned rejection=0;rejection<2;++rejection) {
        input[2].bits=rejection?(uint64_t)-1:7;attempts=0;
        assert(CALL()==(rejection?2:0) && live==0);size_t allocations=attempts;
        for(size_t i=0;i<allocations;++i) {
            attempts=0;fail_at=i;memcpy(output,before,sizeof output);
            assert(CALL()==2 && !strcmp(result.value.execution.code,"OutOfMemory") && live==0);
            assert(!result.value.node_count && !memcmp(output,before,sizeof output));
            fail_at=(size_t)-1;
            assert(CALL()==(rejection?2:0) && live==0);
        }
    }
    return 0;
}
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True,type=Path)
    parser.add_argument('--zig',required=True)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-native-codec-wire-') as directory:
        root=Path(directory);entry=root/'main.my';entry.write_text(MAIN)
        for boxed in (False,True):
            data=DATA.replace('EXPORT_REJECTION','export Rejection;' if boxed else '').replace('REJECTION','struct Rejection{n:i64}' if boxed else '')
            data=data.replace('ERROR_TYPE','Rejection' if boxed else 'i64').replace('ERROR_VALUE','new Rejection{n:-10}' if boxed else '-10')
            data=data.replace('return new Wire{n:unwrap(x)+1};', 'if unwrap(x)==26{return new Wire{n:1/(unwrap(x)-26)};}return new Wire{n:unwrap(x)+1};')
            (root/'data.my').write_text(data)
            (root/'generated.c').write_bytes(invoke([args.compiler,'emit-project-c',entry]).stdout)
            host=root/'host.c';host.write_text(f'#define BOXED {int(boxed)}\n'+TRACKER+HOST)
            for optimize in ('-O0','-O2'):
                binary=root/'host'
                invoke([args.zig,'cc','-std=c11',optimize,'-fsanitize=address,undefined','-fno-sanitize-recover=undefined',host,'-o',binary])
                result=invoke([binary]);assert result.stdout==b'' and result.stderr==b''
                library=root/'library.so'
                invoke([args.zig,'cc','-std=c11',optimize,'-DMYLANG_EMBED','-shared','-fPIC',root/'generated.c','-o',library])
                headers=Path(__file__).resolve().parents[1]/'src'
                public=root/'public.c'
                public.write_text('#include <assert.h>\n#include <string.h>\n#include "native_providers.h"\n#include "native_embed.h"\n'
                    'int main(void){MylangWireNode in[]={{"data::Positive",0,1},{"data::Wire",0,1},{"i64",7,0}},out[3];'
                    'MylangCodecResult result;assert(!mylang_native_call_codecs_v1("main::echo",in,3,out,3,0,&result));'
                    'assert(result.calls==3 && result.value.node_count==3 && out[2].bits==15);return 0;}')
                invoke([args.zig,'cc','-std=c11',optimize,'-I',headers,public,library,'-o',binary])
                result=invoke([binary]);assert result.stdout==b'' and result.stderr==b''
    print('native codec wire: conversion, typed rejection, budgets, unchanged insufficient output, opacity, allocation failures and recovery passed')


if __name__=='__main__':
    main()
