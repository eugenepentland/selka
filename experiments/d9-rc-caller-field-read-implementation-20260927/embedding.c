#include "qbe_runtime.h"
#include "native_rc_internal.h"
#include "native_collections.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef struct { myl_native_list *code; int64_t index; } Cursor;
static uint64_t (*replace_after)(void *,void *),(*read_guest)(void *,void *),(*advance)(void *,void *),(*forward)(void *,void *),(*arithmetic)(void *,void *,uint64_t),(*wide)(void *,void *,void *);
static myl_rc_status (*import_descriptor)(myl_native_heap *,const myl_rc_descriptor *),(*hold_acquire)(myl_native_heap *,void *,myl_rc_hold *);
static void (*hold_release)(myl_native_heap *,myl_rc_hold *);
static void *(*allocate)(myl_native_heap *,const myl_native_type *,size_t);
static void (*release)(myl_native_heap *,void *);
static myl_native_list *(*make_list)(myl_native_heap *,const myl_native_type *,size_t);
static int (*append)(myl_native_heap *,myl_native_list *,const void *);
static myl_rc_allocator original;
static void *context;
static int mode, observed, bad, hooks;
static uint64_t answer;
static Cursor cursor;
static myl_rc_hold held;
static int owner;
static const myl_native_type type={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type extra={.size=3,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_rc_shape extra_shape={.size=3,.kind=MYL_RC_SHAPE_NONE};
static const myl_rc_descriptor extra_descriptor={.type=&extra,.shape=&extra_shape};
static void finalized(myl_native_heap *heap,void *payload) {
    if(*(uint64_t *)payload==2){observed++;return;}
    uint64_t *queued=allocate(heap,&type,1);
    if(!queued){bad=1;return;}*queued=2;release(heap,queued);
    if(observed)bad=2;
    size_t limit=heap->limit; if(mode==14)heap->limit=heap->bytes;
    myl_rc_status status=import_descriptor(heap,&extra_descriptor);heap->limit=limit;
    if(status!=(mode==14?MYL_RC_ALLOCATION_REFUSED:MYL_RC_OK))bad=3;
    answer=forward(context,&cursor);
    if(observed)bad=4;
}
static myl_rc_status wrapped(myl_native_heap *heap,const myl_rc_alloc_request *request,void **out) {
    hooks++;
    if(mode==6){*out=NULL;return MYL_RC_ALLOCATION_REFUSED;}
    return original.allocate(heap,request,out);
}
static void cleanup(void *ctx) {
    myl_native_heap *heap=&((MylQbeContext *)ctx)->heap;
    heap->rc->allocator.hooks=original;
    if(mode==13 && cursor.code)((myl_rc_object *)cursor.code-1)->holds=0;
    if(held.payload)hold_release(heap,&held);
    if(owner&&cursor.code)release(heap,cursor.code);
    cursor.code=NULL;
}
static uint64_t entry(void *ctx) {
    context=ctx;MylQbeContext *state=ctx;myl_native_heap *heap=&state->heap;
    static const myl_rc_shape shape={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&type,.shape=&shape,.finalize=finalized};
    static const myl_native_type element={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    original=heap->rc->allocator.hooks;state->adapter_cleanup=cleanup;
    if(mode==3)heap->region_depth=1;
    if(mode==4)heap->region_depth=2;
    if(import_descriptor(heap,&descriptor)!=MYL_RC_OK){bad=5;return 0;}
    cursor.code=make_list(heap,&element,3);owner=1;
    if(!cursor.code){bad=7;return 0;}
    for(uint64_t i=7;i<=15;i+=4)if(!append(heap,cursor.code,&i)){bad=8;return 0;}
    cursor.index=mode==4?-1:0;
    if(mode==15||mode==16){
        if(hold_acquire(heap,cursor.code,&held)!=MYL_RC_OK){bad=9;return 0;}
        release(heap,cursor.code);owner=0;
    }
    heap->rc->allocator.hooks.allocate=wrapped;
    if(mode==5)state->frame_floor=UINTPTR_MAX;
    if(mode==12)state->frames=1;
    if(mode==2||mode==14){uint64_t *first=allocate(heap,&type,1);if(!first){bad=6;return 0;}*first=1;release(heap,first);}
    else if(mode==7){cursor.index=99;answer=advance(ctx,&cursor);}
    else if(mode==8)answer=arithmetic(ctx,&cursor,INT64_MAX);
    else if(mode==6)answer=replace_after(ctx,&cursor);
    else if(mode==5||mode==9||mode==10){static uint64_t padding[4096];if(mode==10)heap->limit=heap->bytes;answer=wide(ctx,&cursor,padding);}
    else if(mode==13){((myl_rc_object *)cursor.code-1)->holds=MYL_RC_COUNT_MAX-1;answer=read_guest(ctx,&cursor);}
    else if(mode==16)answer=forward(ctx,&cursor);
    else answer=advance(ctx,&cursor);
    return 0;
}
int main(int argc,char **argv) {
    if(argc!=9)return 2;mode=atoi(argv[8]);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!library){fprintf(stderr,"%s\n",dlerror());return 3;}
    read_guest=dlsym(library,argv[2]);advance=dlsym(library,argv[3]);forward=dlsym(library,argv[4]);arithmetic=dlsym(library,argv[5]);wide=dlsym(library,argv[6]);replace_after=dlsym(library,argv[7]);
    import_descriptor=dlsym(library,"myl_rc_descriptor_import");allocate=dlsym(library,"myl_native_heap_alloc");release=dlsym(library,"myl_rc_owner_release");
    hold_acquire=dlsym(library,"myl_rc_hold_acquire");hold_release=dlsym(library,"myl_rc_hold_release");
    make_list=dlsym(library,"myl_native_list_new");append=dlsym(library,"myl_native_list_append");
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!replace_after||!read_guest||!advance||!forward||!arithmetic||!wide||!import_descriptor||!allocate||!release||!initialize||!execute||!make_list||!append||!hold_acquire||!hold_release)return 4;
    MylQbeResult result={0};int status=execute(entry,mode==11?12:MYL_QBE_UNBOUNDED,mode==12?1:MYL_QBE_UNBOUNDED,0,NULL,initialize,&result);
    printf("mode=%d status=%d observed=%d hooks=%d bad=%d result=%llu index=%lld code=%s line=%llu\n",mode,status,observed,hooks,bad,(unsigned long long)answer,(long long)cursor.index,result.code?result.code:"none",(unsigned long long)(result.trace_count?result.trace[0].line:0));
    int trapped=(mode>=5&&mode<=8)||mode==11||mode==12;
    int failed=bad||(mode==13?0:(trapped?!status:status||answer!=((mode==9||mode==10)?10:mode==4?15:7)));
    if(mode==2||mode==14)failed|=observed!=1;
    dlclose(library);return failed;
}
