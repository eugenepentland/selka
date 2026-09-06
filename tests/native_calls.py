"""Native public scalar calls: visibility, exact wire values, failures and recovery."""
import argparse
from pathlib import Path
import tempfile
import sys
from native_embedding import TRACKER, invoke

HOST = r'''
static void failure(const char *name, MylangScalar *args, size_t n, const char *code) {
    MylangCallResult result;
    int status=mylang_native_call_v1(name,args,n,NULL,&result);
    if(status!=2) fprintf(stderr,"failure case %s expected %s got %d\n",name,code,status);
    assert(status==2);
    assert(!strcmp(result.execution.code,code) && live==0 && result.value.type==NULL);
}
int main(void) {
    MylangCallResult result;
    MylangScalar arg={"i64",7};
    assert(mylang_native_call_v1("main::zero",NULL,0,NULL,&result)==0 && result.value.bits==1 && !strcmp(result.value.type,"bool") && live==0);
    assert(mylang_native_call_v1("main::forward",&arg,1,NULL,NULL)==2);
    failure(NULL,&arg,1,"InvalidArgument");
    failure("main::forward",NULL,1,"InvalidArgument");
    failure("main::hidden",&arg,1,"UnknownFunction");
    failure("lib::identity::<i64>",&arg,1,"UnknownFunction");
    failure("main::missing",&arg,1,"UnknownFunction");
    failure("main::aggregate",NULL,0,"UnsupportedSignature");
    failure("main::view",NULL,0,"UnsupportedSignature");
    failure("main::forward",&arg,0,"InvalidArgument");
    arg.type=NULL; failure("main::forward",&arg,1,"InvalidArgument");
    arg.type="u64"; failure("main::forward",&arg,1,"InvalidArgument");
    const char *types[]={"i8","i16","i32","i64","u8","u16","u32","u64","bool"};
    const uint64_t maxima[]={127,32767,2147483647,INT64_MAX,255,65535,UINT32_MAX,UINT64_MAX,1};
    const uint64_t minima[]={UINT64_MAX-127,UINT64_MAX-32767,UINT64_MAX-2147483647,UINT64_C(1)<<63,0,0,0,0,0};
    const char *names[]={"main::echo_i8","main::echo_i16","main::echo_i32","main::echo_i64","main::echo_u8","main::echo_u16","main::echo_u32","main::echo_u64","main::echo_bool"};
    for(size_t i=0;i<9;++i) {
        arg.type=types[i];
        for(unsigned j=0;j<2;++j) {
            arg.bits=j ? maxima[i] : minima[i];
            assert(mylang_native_call_v1(names[i],&arg,1,NULL,&result)==0 && live==0);
            assert(!strcmp(result.value.type,types[i]) && result.value.bits==arg.bits);
        }
        if(i!=3 && i!=7) {
            arg.bits=maxima[i]+1; failure(names[i],&arg,1,"InvalidArgument");
        }
        if(i<3) { arg.bits=minima[i]-1;failure(names[i],&arg,1,"InvalidArgument"); }
    }
    MylangScalar pair[]={{"i64",1},{"u64",2}};
    failure("main::add",pair,2,"InvalidArgument"); /* release earlier copied argument */
    pair[1].type="i64";
    assert(mylang_native_call_v1("main::add",pair,2,NULL,&result)==0 && result.value.bits==3 && live==0);
    arg=(MylangScalar){"i64",0};
    assert(mylang_native_call_v1("main::divide",&arg,1,NULL,&result)==1 && live==0);
    assert(!strcmp(result.execution.code,"R_DIVISION_BY_ZERO") && result.execution.frame_count);
    assert(!strcmp(result.execution.frames[0].function,"main::divide"));
    assert(result.execution.path && result.execution.line && !result.value.type);
    MylangRunOptions options={.max_steps=1};
    arg.bits=7;
    assert(mylang_native_call_v1("main::forward",&arg,1,&options,&result)==1 && live==0);
    assert(!strcmp(result.execution.code,"R_STEP_LIMIT"));
    attempts=0;
    assert(mylang_native_call_v1("main::forward",&arg,1,NULL,&result)==0 && live==0);
    size_t allocations=attempts;
    for(size_t i=0;i<allocations;++i) {
        attempts=0;fail_at=i;
        failure("main::forward",&arg,1,"OutOfMemory");
        fail_at=(size_t)-1;
        assert(mylang_native_call_v1("main::forward",&arg,1,NULL,&result)==0 && live==0 && result.value.bits==7);
    }
    for(unsigned i=0;i<32;++i) {
        MylangRunResult entry;
        assert(mylang_native_run_v1(NULL,&entry)==0 && entry.value==9 && live==0);
        assert(mylang_native_call_v1("main::forward",&arg,1,NULL,&result)==0 && result.value.bits==7 && live==0);
        assert(mylang_native_call_v1("lib::public",&arg,1,NULL,&result)==0 && result.value.bits==8 && live==0);
    }
    return 0;
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-native-calls-') as directory:
        tmp = Path(directory)
        (tmp/'lib.my').write_text('module lib; export public; export identity; fn identity<T:copy>(x:T)->T{return x;} fn public(x:i64)->i64{return identity::<i64>(x)+1;}')
        source = '''module main; import lib;
export Pair; export zero; export forward; export add; export divide; export aggregate; export view;
struct Pair { x:i64 }
fn zero()->bool{return true;}
fn hidden(x:i64)->i64{return x;}
fn forward(x:i64)->i64{return lib::public(x)-1;}
fn add(x:i64,y:i64)->i64{return x+y;}
fn divide(x:i64)->i64{return 1/x;}
fn aggregate()->Pair{return new Pair {x:1};}
fn view(x:&i64)->&i64 from x{return x;}
fn main()->i64{return 9;}
'''
        for ty in ('i8','i16','i32','i64','u8','u16','u32','u64','bool'):
            source=source.replace('import lib;',f'import lib; export echo_{ty};')
            source+=f'fn echo_{ty}(x:{ty})->{ty}{{return x;}}\n'
        entry=tmp/'main.my'
        entry.write_text(source)
        (tmp/'generated.c').write_bytes(invoke([args.compiler,'emit-project-c',entry]).stdout)
        host=tmp/'host.c'
        host.write_text(TRACKER+HOST)
        for mode in ('-O0','-O2'):
            binary=tmp/'host'
            invoke([args.zig,'cc','-std=c11',mode,'-fsanitize=undefined','-fno-sanitize-recover=undefined',host,'-o',binary])
            result=invoke([binary])
            assert result.stdout==b'' and result.stderr==b''
        root=Path(__file__).resolve().parents[1]
        library=tmp/'libguest.so'
        linked=tmp/'linked.c'
        linked.write_text('''#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <string.h>
int main(void){
    MylangScalar arg={"u64",UINT64_MAX};MylangCallResult result;
    assert(mylang_native_call_v1("main::echo_u64",&arg,1,0,&result)==0);
    assert(result.value.bits==UINT64_MAX && !strcmp(result.value.type,"u64"));
    arg=(MylangScalar){"i64",7};
    assert(mylang_native_call_v1("main::forward",&arg,1,0,&result)==0 && result.value.bits==7);
    return 0;
}
''')
        for mode in ('Debug','ReleaseFast'):
            invoke([sys.executable,root/'scripts/native.py',entry,'--project','--library','--mode',mode,'--compiler',args.compiler,'--zig',args.zig,'-o',library])
            binary=tmp/'linked-host'
            invoke([args.zig,'cc',linked,'-I',root/'src',library,'-o',binary])
            result=invoke([binary])
            assert result.stdout==b'' and result.stderr==b''
    print('native calls: public visibility, scalar widths, invalid inputs, traps, budgets, allocation recovery and entry interleaving passed in -O0/-O2')


if __name__=='__main__':
    main()
