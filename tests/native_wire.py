"""Native ordinary-value wire calls: independent host trees and bounded ownership."""
import argparse
from pathlib import Path
import tempfile
import sys
from native_embedding import TRACKER, invoke

SOURCE = '''module main;
export File;export PrivateWrap;export codes;export echo_codes;export file_value;export opaque_wrapper;export Pair;export Other;export Small;export Nested;export Box;export Color;export Outcome;export D;
export make;export change;export pack;export box_value;export empty;export empty_array;export color;export outcome;export opaque;export trap;
resource File:filesystem;struct PrivateWrap{d:D}
fn file_value(x:File)->File{return x;}fn opaque_wrapper(x:PrivateWrap)->PrivateWrap{return x;}
fn codes()->[Color]u16{return new [Color]u16{red:200u16,blue:404u16};}
fn echo_codes(x:[Color]u16)->[Color]u16{return x;}
struct Pair{a:[2]i64,flag:bool} struct Other{a:[2]i64,flag:bool}
union Small{none,num:i64} union Nested{none,inner:Small} union Box{none,data:Pair}
enum Color{red,blue} result Outcome{ok:Pair,err:i64} domain D:i64{}
fn make()->Pair{return new Pair{a:new [2]i64[7,8],flag:true};}
fn change(p:Pair)->Pair{return update(p){a:replace(p.a,0,9),flag:false};}
fn pack(p:Small)->Nested{return new Nested.inner(p);}
fn box_value(p:Pair)->Box{return new Box.data(p);}
fn empty()->Box{return new Box.none;}
fn empty_array()->[0]i64{return new [0]i64[];}
fn color(c:Color)->Color{return c;}
fn outcome(p:Outcome)->Outcome{return p;}
fn opaque(p:D)->D{return p;}
fn trap(p:Pair)->i64{return p.a[2];}
fn main()->i64{return 0;}
'''
HOST = r'''
static MylangWireNode output[32];
static MylangWireResult result;
static void success(const char *name, const MylangWireNode *input, size_t count, size_t expected) {
    int status=mylang_native_call_values_v1(name,input,count,output,32,NULL,&result);
    if(status) fprintf(stderr,"call %s failed: %s\n",name,result.execution.code);
    assert(status==0);
    assert(result.node_count==expected && live==0);
}
static void failure(const char *name, const MylangWireNode *input, size_t count, const char *code) {
    memset(output,0x55,sizeof output);
    assert(mylang_native_call_values_v1(name,input,count,output,32,NULL,&result)==2);
    assert(!strcmp(result.execution.code,code) && result.node_count==0 && live==0);
    for(size_t i=0;i<sizeof output;++i) assert(((unsigned char *)output)[i]==0x55);
}
int main(void) {
    success("main::codes",NULL,0,3);
    assert(output[0].children==2 && output[1].bits==200 && output[2].bits==404);
    MylangWireNode codes[3];memcpy(codes,output,sizeof codes);
    success("main::echo_codes",codes,3,3);assert(output[2].bits==404);
    failure("main::file_value",NULL,0,"UnsupportedSignature");
    failure("main::opaque_wrapper",NULL,0,"UnsupportedSignature");
    success("main::make",NULL,0,5);
    assert(!strcmp(output[0].type,"main::Pair") && output[0].children==2);
    assert(output[1].children==2 && output[2].bits==7 && output[3].bits==8 && output[4].bits==1);
    MylangWireNode original[5]; memcpy(original,output,sizeof original);
    success("main::change",original,5,5);
    assert(output[2].bits==9 && output[3].bits==8 && output[4].bits==0 && original[2].bits==7);
    success("main::box_value",original,5,6);
    assert(!strcmp(output[0].type,"main::Box") && output[0].bits==1 && output[0].children==1);
    assert(output[3].bits==7 && output[5].bits==1);
    success("main::empty",NULL,0,1); assert(output[0].bits==0 && output[0].children==0);
    success("main::empty_array",NULL,0,1); assert(output[0].bits==0 && output[0].children==0);
    MylangWireNode small[]={{"main::Small",1,1},{"i64",UINT64_MAX,0}};
    success("main::pack",small,2,3);
    assert(!strcmp(output[0].type,"main::Nested") && output[0].bits==1);
    assert(output[1].bits==1 && output[2].bits==UINT64_MAX);
    small[0].bits=0;small[0].children=0;
    success("main::pack",small,1,2);assert(output[1].bits==0 && output[1].children==0);
    MylangWireNode color={"main::Color",1,0};
    success("main::color",&color,1,1);assert(output[0].bits==1);
    color.bits=2;failure("main::color",&color,1,"InvalidArgument");
    MylangWireNode outcome[6]={{"main::Outcome",0,1}};
    memcpy(outcome+1,original,sizeof original);
    success("main::outcome",outcome,6,6);assert(output[0].bits==0 && output[3].bits==7);
    outcome[0].bits=1;outcome[1]=(MylangWireNode){"i64",UINT64_MAX,0};
    success("main::outcome",outcome,2,2);assert(output[1].bits==UINT64_MAX);
    failure("main::opaque",NULL,0,"UnsupportedSignature");
    failure("main::missing",NULL,0,"UnknownFunction");
    failure("main::change",original,4,"InvalidArgument");
    failure("main::make",original,5,"InvalidArgument");
    MylangWireNode bad[5]; memcpy(bad,original,sizeof bad);
    bad[0].type="main::Other";failure("main::change",bad,5,"InvalidArgument");
    memcpy(bad,original,sizeof bad);bad[0].children=1;failure("main::change",bad,5,"InvalidArgument");
    memcpy(bad,original,sizeof bad);bad[1].bits=1;failure("main::change",bad,5,"InvalidArgument");
    memcpy(bad,original,sizeof bad);bad[4].bits=2;failure("main::change",bad,5,"InvalidArgument");
    memcpy(bad,original,sizeof bad);bad[3].type=NULL;failure("main::change",bad,5,"InvalidArgument");
    failure("main::change",original,100001,"WireLimit");
    memset(output,0x55,sizeof output);
    assert(mylang_native_call_values_v1("main::make",NULL,0,output,4,NULL,&result)==2);
    assert(!strcmp(result.execution.code,"OutputTooSmall") && result.node_count==5 && live==0);
    for(size_t i=0;i<sizeof output;++i) assert(((unsigned char *)output)[i]==0x55);
    assert(mylang_native_call_values_v1("main::make",NULL,0,NULL,0,NULL,&result)==2 && result.node_count==5 && live==0);
    assert(mylang_native_call_values_v1("main::trap",original,5,output,32,NULL,&result)==1 && live==0);
    assert(!strcmp(result.execution.code,"R_INDEX_BOUNDS") && result.execution.frame_count && result.node_count==0);
    for(unsigned pass=0;pass<2;++pass) {
        const char *name=pass ? "main::box_value" : "main::change";
        attempts=0;success(name,original,5,pass ? 6 : 5);
        size_t allocations=attempts;
        for(size_t i=0;i<allocations;++i) {
            attempts=0;fail_at=i;failure(name,original,5,"OutOfMemory");fail_at=(size_t)-1;
            success(name,original,5,pass ? 6 : 5);
        }
    }
    for(unsigned i=0;i<32;++i) success("main::change",original,5,5);
    return 0;
}
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True,type=Path)
    parser.add_argument('--zig',required=True)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-wire-') as directory:
        root=Path(directory)
        entry=root/'main.my';entry.write_text(SOURCE)
        (root/'generated.c').write_bytes(invoke([args.compiler,'emit-project-c',entry]).stdout)
        host=root/'host.c';host.write_text(TRACKER+HOST)
        for mode in ('-O0','-O2'):
            binary=root/'host'
            invoke([args.zig,'cc','-std=c11',mode,'-fsanitize=address,undefined','-fno-sanitize-recover=undefined',host,'-o',binary])
            result=invoke([binary]);assert result.stdout==b'' and result.stderr==b''
        repository=Path(__file__).resolve().parents[1]
        linked=root/'linked.c'
        linked.write_text('''#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <string.h>
int main(void){
    MylangWireNode value[5],out[5];MylangWireResult result;
    assert(mylang_native_call_values_v1("main::make",0,0,value,5,0,&result)==0 && result.node_count==5);
    assert(mylang_native_call_values_v1("main::change",value,5,out,5,0,&result)==0 && result.node_count==5);
    assert(!strcmp(out[0].type,"main::Pair") && out[2].bits==9 && value[2].bits==7);
    return 0;
}
''')
        for mode in ('Debug','ReleaseFast'):
            library=root/'libguest.so'
            invoke([sys.executable,repository/'scripts/native.py',entry,'--project','--library','--mode',mode,'--compiler',args.compiler,'--zig',args.zig,'-o',library])
            binary=root/'linked-host'
            invoke([args.zig,'cc',linked,'-I',repository/'src',library,'-o',binary])
            result=invoke([binary]);assert result.stdout==b'' and result.stderr==b''
        # Exact 128-level acceptance and rejection on each side of the boundary.
        declarations='struct Deep0{value:i64}\n'
        for i in range(1,128):
            declarations+=f'struct Deep{i}{{value:Deep{i-1}}}\n'
        expression='new Deep0{value:7}'
        for i in range(1,128):
            expression=f'new Deep{i}{{value:{expression}}}'
        source='module main;export Big;export big;'+''.join(f'export Deep{i};' for i in range(128))+'export exact;export too_deep;export deep_result;'
        source+='struct Big{a:[49998]u8,b:[49999]u8}fn big(x:Big)->Big{return x;}'
        source+=declarations+'fn exact(x:Deep126)->Deep126{return x;}fn too_deep(x:Deep127)->Deep127{return x;}fn main()->i64{return 0;}'
        source+='fn deep_result()->Deep127{return '+expression+';}'
        entry.write_text(source)
        (root/'generated.c').write_bytes(invoke([args.compiler,'emit-project-c',entry]).stdout)
        host.write_text(TRACKER+r'''
int main(void){
    char names[128][32];MylangWireNode in[129],out[129];MylangWireResult result;
    MylangWireNode *big_in=calloc(100000,sizeof(*big_in)),*big_out=calloc(100000,sizeof(*big_out));
    assert(big_in && big_out);
    big_in[0]=(MylangWireNode){"main::Big",0,2};
    big_in[1]=(MylangWireNode){"[49998]u8",0,49998};
    for(size_t i=2;i<50000;++i) big_in[i]=(MylangWireNode){"u8",255,0};
    big_in[50000]=(MylangWireNode){"[49999]u8",0,49999};
    for(size_t i=50001;i<100000;++i) big_in[i]=(MylangWireNode){"u8",255,0};
    assert(mylang_native_call_values_v1("main::big",big_in,100000,big_out,100000,NULL,&result)==0 && result.node_count==100000 && live==0);
    assert(big_out[99999].bits==255);
    free(big_in);free(big_out);
    for(size_t i=0;i<128;++i){snprintf(names[i],32,"main::Deep%zu",127-i);in[i]=(MylangWireNode){names[i],0,1};}
    in[128]=(MylangWireNode){"i64",7,0};
    assert(mylang_native_call_values_v1("main::exact",in+1,128,out,129,NULL,&result)==0 && result.node_count==128 && live==0);
    assert(out[127].bits==7);
    assert(mylang_native_call_values_v1("main::too_deep",in,129,out,129,NULL,&result)==2 && !strcmp(result.execution.code,"WireLimit") && result.node_count==0 && live==0);
    assert(mylang_native_call_values_v1("main::deep_result",NULL,0,out,129,NULL,&result)==2 && !strcmp(result.execution.code,"WireLimit") && result.node_count==0 && live==0);
    assert(mylang_native_call_values_v1("main::exact",in+1,128,out,129,NULL,&result)==0 && live==0);
    return 0;
}
''')
        for mode in ('-O0','-O2'):
            binary=root/'deep-host'
            invoke([args.zig,'cc','-std=c11',mode,'-fsanitize=address,undefined','-fno-sanitize-recover=undefined',host,'-o',binary])
            result=invoke([binary]);assert result.stdout==b'' and result.stderr==b''
    print('native wire: records, arrays, packed/boxed variants, enum/results, rejection, output capacity, traps, allocation failures and repeated recovery passed')


if __name__=='__main__':
    main()
