"""Exercise generated C as a returning, repeatable host library with allocation recovery."""
import argparse
import json
import sys
from pathlib import Path
import subprocess
import tempfile

TRACKER = r'''
#include <assert.h>
#include <stdlib.h>
#include <string.h>
static size_t live, attempts, fail_at = (size_t)-1;
static void *tracked_malloc(size_t n) {
    if (attempts++ == fail_at) return NULL;
    void *p=malloc(n); if(p) ++live; return p;
}
static void *tracked_calloc(size_t n,size_t s) {
    if (attempts++ == fail_at) return NULL;
    void *p=calloc(n,s); if(p) ++live; return p;
}
static void *tracked_realloc(void *p,size_t n) {
    if (attempts++ == fail_at) return NULL;
    int fresh=p==NULL; void *q=realloc(p,n); if(q && fresh) ++live; return q;
}
static void tracked_free(void *p) { if(p) {assert(live);--live;} free(p); }
#define malloc tracked_malloc
#define calloc tracked_calloc
#define realloc tracked_realloc
#define free tracked_free
#define MYLANG_EMBED
#include "generated.c"
#undef malloc
#undef calloc
#undef realloc
#undef free
'''
HARNESS = r'''
#include <pthread.h>
static unsigned calls, resource_live;
static void *overlap(void *context) {
    (void)context; MylangRunResult nested;
    assert(mylang_native_run_v1(NULL,&nested)==2 && !strcmp(nested.code,"Busy"));
    return NULL;
}
static MylangResourceResult acquire_file(void *c,const uint8_t *p,size_t n,unsigned permissions) {
    (void)c;(void)p;(void)n;(void)permissions; ++resource_live;
    return (MylangResourceResult){MYLANG_PROVIDER_OK,7};
}
static MylangProviderStatus complete_file(void *c,uint64_t handle) {
    (void)c;(void)handle; assert(resource_live);--resource_live;return MYLANG_PROVIDER_OK;
}
static void release_file(void *c,uint64_t handle) {
    (void)c;(void)handle;assert(resource_live);--resource_live;
}
static MylangClockResult clock_value(void *context) {
    (void)context; ++calls;
    MylangRunResult nested;
    assert(mylang_native_run_v1(NULL,&nested)==2);
    assert(!strcmp(nested.code,"Busy"));
    MylangCallResult named;
    assert(mylang_native_call_v1("missing",NULL,0,NULL,&named)==2 && !strcmp(named.execution.code,"Busy"));
    MylangWireResult wire;
    assert(mylang_native_call_values_v1("missing",NULL,0,NULL,0,NULL,&wire)==2 && !strcmp(wire.execution.code,"Busy"));
    MylangCodecResult codec;
    assert(mylang_native_call_codecs_v1("missing",NULL,0,NULL,0,NULL,&codec)==2 && !strcmp(codec.value.execution.code,"Busy"));
    assert(!codec.calls && !codec.rejected && !codec.value.node_count);
    pthread_t thread; assert(!pthread_create(&thread,NULL,overlap,NULL)); assert(!pthread_join(thread,NULL));
    return (MylangClockResult){MYLANG_PROVIDER_OK,7};
}
int main(void) {
    MylangNativeProviders supplied={.clock_now=clock_value,.filesystem={.acquire=acquire_file,.complete=complete_file,.release=release_file}};
    MylangRunOptions config={.providers=&supplied};
    MylangRunResult result;
    assert(mylang_native_run_v1(&config,NULL)==2);
    for(unsigned i=0;i<32;++i) {
        assert(mylang_native_run_v1(&config,&result)==EXPECTED_STATUS);
        assert(live==0 && resource_live==0 && result.steps>0);
        if(EXPECTED_STATUS==0) assert(result.value==EXPECTED_VALUE && result.code==NULL);
        else assert(!strcmp(result.code,"R_DIVISION_BY_ZERO") && result.frame_count && result.path && result.line);
    }
    if(FRAME_TEST) {
        config.max_frames=18;
        assert(mylang_native_run_v1(&config,&result)==1 && !strcmp(result.code,"R_FRAME_LIMIT"));
        assert(result.frame_count==16 && result.omitted_frames>0 && live==0 && resource_live==0);
        config.max_frames=0;
    }
    config.max_steps=1;
    assert(mylang_native_run_v1(&config,&result)==1);
    assert(!strcmp(result.code,"R_STEP_LIMIT") && live==0 && resource_live==0);
    config.max_steps=0;
    supplied.filesystem.permissions=8;
    assert(mylang_native_run_v1(&config,&result)==2);
    assert(!strcmp(result.code,"InvalidCapability") && live==0 && resource_live==0);
    supplied.filesystem.permissions=0;
    attempts=0; fail_at=(size_t)-1;
    assert(mylang_native_run_v1(&config,&result)==EXPECTED_STATUS);
    size_t allocations=attempts;
    for(size_t index=0;index<allocations;++index) {
        attempts=0;fail_at=index;
        assert(mylang_native_run_v1(&config,&result)==2);
        assert(!strcmp(result.code,"OutOfMemory") && live==0 && resource_live==0);
        fail_at=(size_t)-1;
        assert(mylang_native_run_v1(&config,&result)==EXPECTED_STATUS && live==0 && resource_live==0);
    }
    assert(mylang_native_run_v1(NULL,&result)==MISSING_STATUS && live==0 && resource_live==0);
    if(MISSING_STATUS==2) assert(!strcmp(result.code,"CapabilityUnavailable"));
    assert(mylang_native_run_v1(&config,&result)==EXPECTED_STATUS && live==0 && resource_live==0);
    return 0;
}
'''

def invoke(argv):
    result = subprocess.run([str(x) for x in argv], capture_output=True, timeout=180)
    assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    fixtures = [
        ('recursive', 'fn depth(n:i64)->i64{if n==0{return 7;}return depth(n-1);}fn main()->i64{return depth(20);}', 0, 7, 0),
        ('resource-trap', 'resource File:filesystem;result Open{ok:File,err:i64}fn divide(n:i64)->i64{return 1/n;}fn main(fs:filesystem_cap)->i64{match acquire_resource<Open>(fs,new [0]u8 []){Open.ok(f)=>{let value=divide(0);discard f;return value;},Open.err(e)=>{return e;}}}', 1, 0, 2),
        ('resource', 'resource File:filesystem;result Open{ok:File,err:i64}fn main(fs:filesystem_cap)->i64{match acquire_resource<Open>(fs,new [0]u8 []){Open.ok(f)=>{discard f;return 7;},Open.err(e)=>{return e;}}}', 0, 7, 2),
        ('scalar', 'fn main()->i64{return 7;}', 0, 7, 0),
        ('trap', 'fn divide(x:i64)->i64{return 1/x;}fn main()->i64{return divide(0);}', 1, 0, 1),
        ('clock', 'result Time{ok:i64,err:i64}fn main(c:clock_cap)->i64{match clock_now<Time>(c){Time.ok(n)=>{return n;},Time.err(e)=>{return e;}}}', 0, 7, 2),
    ]
    for name, expected in (('generics',25), ('generic-returned-references',22), ('arenas',None), ('pools',None), ('arena-reset',None), ('buffers',None)):
        fixtures.append((name,(root/'examples'/f'{name}.my').read_text(),0,expected,0))
    with tempfile.TemporaryDirectory(prefix='mylang-embedding-') as directory:
        temporary = Path(directory)
        for name, source, status, value, missing in fixtures:
            entry = temporary/'entry.my'
            entry.write_text(source)
            if value is None:
                value = int(invoke([args.compiler,'run',entry]).stdout)
            (temporary/'generated.c').write_bytes(invoke([args.compiler,'emit-c',entry]).stdout)
            harness = temporary/'host.c'
            harness.write_text(f'#define FRAME_TEST {int(name == "recursive")}\n#define EXPECTED_STATUS {status}\n#define EXPECTED_VALUE {value}\n#define MISSING_STATUS {missing}\n'+TRACKER+HARNESS)
            for mode in ('-O0','-O2'):
                binary = temporary/'host'
                invoke([args.zig,'cc','-std=c11',mode,'-pthread','-fsanitize=undefined','-fno-sanitize-recover=undefined',harness,'-o',binary])
                result = invoke([binary])
                assert result.stdout == b'' and result.stderr == b'', (name,result.stdout,result.stderr)
        entry.write_text('fn main()->i64{return 7;}')
        header_host = temporary/'linked-host.c'
        header_host.write_text('#include "native_providers.h"\n#include "native_embed.h"\n#include <assert.h>\nint main(void){MylangRunResult r;assert(mylang_native_run_v1(0,&r)==0 && r.value==7);return 0;}\n')
        for mode in ('Debug','ReleaseFast'):
            library = temporary/'libguest.so'
            command = [sys.executable,root/'scripts/native.py',entry,'--compiler',args.compiler,'--zig',args.zig,'--library','--mode',mode,'--report','-o',library]
            report = json.loads(invoke(command).stdout)
            assert report['artifact_kind']=='shared-library'
            before = library.stat()
            again = json.loads(invoke(command).stdout)
            assert not again['output_changed'] and library.stat().st_ino==before.st_ino
            binary = temporary/'linked-host'
            invoke([args.zig,'cc',header_host,'-I',root/'src',library,'-o',binary])
            result = invoke([binary])
            assert result.stdout==b'' and result.stderr==b''
    print(f'native embedding: {len(fixtures)*2} host programs passed repeated calls, traps, budgets, Busy rejection and allocation recovery')


if __name__ == '__main__':
    main()
