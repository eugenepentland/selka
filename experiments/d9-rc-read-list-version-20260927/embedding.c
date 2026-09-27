#include "qbe_runtime.h"
#include "native_rc_internal.h"
#include "native_collections.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t (*fold)(void *,void *),(*fresh)(void *,uint64_t),(*indexed)(void *,void *,uint64_t,uint64_t,uint64_t),(*wide)(void *,void *,void *);
static myl_rc_status (*import_descriptor)(myl_native_heap *,const myl_rc_descriptor *);
static void *(*allocate)(myl_native_heap *,const myl_native_type *,size_t);
static myl_native_list *(*make_list)(myl_native_heap *,const myl_native_type *,size_t);
static int (*append)(myl_native_heap *,myl_native_list *,const void *);
static void (*release)(myl_native_heap *,void *);
static myl_rc_allocator original;
static void *context;
static int mode, observed, bad, hooks, saturated;
static uint64_t answer;
static myl_native_list *list;
static const myl_native_type type={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type extra={.size=3,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_rc_shape extra_shape={.size=3,.kind=MYL_RC_SHAPE_NONE};
static const myl_rc_descriptor extra_descriptor={.type=&extra,.shape=&extra_shape};
static void finalized(myl_native_heap *heap,void *payload) {
    if(*(uint64_t *)payload==2){ observed++; return; }
    uint64_t *queued=allocate(heap,&type,1);
    if(!queued){bad=1;return;} *queued=2;release(heap,queued);
    if(observed)bad=2;
    if(import_descriptor(heap,&extra_descriptor)!=MYL_RC_OK)bad=3;
    answer=fold(context,list);
    if(observed)bad=4;
}
static myl_rc_status wrapped(myl_native_heap *heap,const myl_rc_alloc_request *request,void **out) {
    hooks++;
    if(mode==9){*out=NULL;return MYL_RC_ALLOCATION_REFUSED;}
    return original.allocate(heap,request,out);
}
static void cleanup(void *ctx) {
    myl_native_heap *heap=&((MylQbeContext *)ctx)->heap;
    heap->rc->allocator.hooks=original;
    if(saturated){((myl_rc_object *)list-1)->holds=0;saturated=0;}
    release(heap,list);list=NULL;
}
static uint64_t entry(void *ctx) {
    context=ctx;
    MylQbeContext *state=ctx;myl_native_heap *heap=&state->heap;
    static const myl_rc_shape shape={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&type,.shape=&shape,.finalize=finalized};
    original=heap->rc->allocator.hooks;
    state->adapter_cleanup=cleanup;
    if(mode==4)heap->region_depth=1;
    /* A distinct plain element descriptor prevents accidentally adding a
       finalizer to list scalar storage. */
    static const myl_native_type element={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    list=make_list(heap,&element,65);
    if(!list){bad=5;return 0;}
    for(uint64_t i=0;i<65;i++)if(!append(heap,list,&i)){bad=6;return 0;}
    if(mode==3)heap->region_depth=1;
    if(import_descriptor(heap,&descriptor)!=MYL_RC_OK){bad=7;return 0;}
    heap->rc->allocator.hooks.allocate=wrapped;
    if(mode==10){((myl_rc_object *)list-1)->holds=MYL_RC_COUNT_MAX;saturated=1;}
    if(mode==11)state->frame_floor=UINTPTR_MAX;
    if(mode==14){((uint64_t *)list->storage)[0]=INT64_MAX;((uint64_t *)list->storage)[1]=1;}
    if(mode==12)heap->limit=heap->bytes;
    if(mode==2){uint64_t *first=allocate(heap,&type,1);if(!first){bad=8;return 0;}*first=1;release(heap,first);}
    else if(mode==5||mode==11||mode==12){static uint64_t padding[4096];answer=wide(ctx,padding,list);}
    else if(mode==6)answer=indexed(ctx,list,0,999,0);
    else if(mode==7)answer=indexed(ctx,list,66,0,0);
    else if(mode==8)answer=indexed(ctx,list,2,0,INT64_MAX);
    else if(mode==9)answer=fresh(ctx,65);
    else if(mode==13)answer=fresh(ctx,65);
    else answer=fold(ctx,list);
    return 0;
}
int main(int argc,char **argv) {
    if(argc!=7)return 2;mode=atoi(argv[6]);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 3;}
    fold=dlsym(library,argv[2]);fresh=dlsym(library,argv[3]);indexed=dlsym(library,argv[4]);wide=dlsym(library,argv[5]);
    import_descriptor=dlsym(library,"myl_rc_descriptor_import");allocate=dlsym(library,"myl_native_heap_alloc");
    release=dlsym(library,"myl_rc_owner_release");make_list=dlsym(library,"myl_native_list_new");append=dlsym(library,"myl_native_list_append");
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!fold||!fresh||!indexed||!wide||!import_descriptor||!allocate||!release||!make_list||!append||!initialize||!execute)return 4;
    MylQbeResult result={0};int status=execute(entry,MYL_QBE_UNBOUNDED,MYL_QBE_UNBOUNDED,0,NULL,initialize,&result);
    printf("mode=%d status=%d observed=%d hooks=%d bad=%d result=%llu code=%s line=%llu\n",mode,status,observed,hooks,bad,(unsigned long long)answer,result.code?result.code:"none",(unsigned long long)(result.trace_count?result.trace[0].line:0));
    int trap=(mode>=7&&mode<=11)||mode==14;uint64_t expected=(mode==5||mode==12)?2087:mode==6?7:2080;
    int failed=bad||(trap?!status:status||answer!=expected);
    if(mode==2)failed|=observed!=1;
    dlclose(library);return failed;
}
