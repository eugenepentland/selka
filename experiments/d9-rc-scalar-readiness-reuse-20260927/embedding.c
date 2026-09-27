#include "qbe_runtime.h"
#include "native_rc_internal.h"
#include "native_collections.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t (*grow)(void *,uint64_t),(*written)(void *,uint64_t),(*wide)(void *,void *,uint64_t);
static myl_rc_status (*import_descriptor)(myl_native_heap *,const myl_rc_descriptor *);
static void *(*allocate)(myl_native_heap *,const myl_native_type *,size_t);
static void (*release)(myl_native_heap *,void *),(*edge_release)(myl_native_heap *,void *);
static myl_rc_allocator original;
static void *context;
static int mode, depth, observed, bad, hooks, injected;
static size_t observed_length;
static uint64_t answer;
static myl_native_list *list;
static const myl_native_type type={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type extra={.size=3,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_rc_shape extra_shape={.size=3,.kind=MYL_RC_SHAPE_NONE};
static const myl_rc_descriptor extra_descriptor={.type=&extra,.shape=&extra_shape};
static void finalized(myl_native_heap *heap,void *payload) {
    uint64_t value=*(uint64_t *)payload;
    if(value==2){ observed++; if(depth!=1)bad=10; return; }
    if(value==3){ observed++; observed_length=list?list->length:999; if(import_descriptor(heap,&extra_descriptor)!=MYL_RC_OK)bad=11; return; }
    depth=1;
    uint64_t *queued=allocate(heap,&type,1);
    if(!queued){bad=12;return;} *queued=2; release(heap,queued);
    if(observed)bad=13;
    answer=grow(context,65);
    if(observed)bad=14;
    /* Outer drain alone may now process its queued sibling. */
}
static myl_rc_status wrapped(myl_native_heap *heap,const myl_rc_alloc_request *request,void **out) {
    hooks++;
    if(mode==4 && request->element->size==1 && request->count>=128){ *out=NULL; return MYL_RC_ALLOCATION_REFUSED; }
    if(mode==9 && list && request->element->size==1 && list->length==8)heap->limit=1;
    myl_rc_status status=original.allocate(heap,request,out);
    if(status!=MYL_RC_OK)return status;
    if(request->count==1 && request->element->size==sizeof(myl_native_list))list=*out;
    if(list && request->element->size==1 && list->length==8 && !injected){
        injected=1;
        if(mode==2){
            uint64_t *queued=allocate(heap,&type,1);
            if(!queued){bad=15;return status;}
            *queued=3;edge_release(heap,queued);
        } else if(mode==3)list->generation=UINT64_MAX-1;
    }
    return status;
}
static uint64_t entry(void *ctx) {
    context=ctx;
    myl_native_heap *heap=&((MylQbeContext *)ctx)->heap;
    static const myl_rc_shape shape={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&type,.shape=&shape,.finalize=finalized};
    if(import_descriptor(heap,&descriptor)!=MYL_RC_OK){bad=1;return 0;}
    if(mode==8)heap->limit=heap->bytes;
    if(mode==12)((MylQbeContext *)ctx)->frame_floor=UINTPTR_MAX;
    if(mode==13)((MylQbeContext *)ctx)->frames=((MylQbeContext *)ctx)->frame_limit;
    original=heap->rc->allocator.hooks;
    heap->rc->allocator.hooks.allocate=wrapped;
    if(mode==1){uint64_t *first=allocate(heap,&type,1);if(!first){bad=2;return 0;}*first=1;release(heap,first);}
    else if(mode==5||mode==12){static uint64_t padding[4096];answer=wide(ctx,padding,65);}
    else if(mode==6)answer=written(ctx,65);
    else answer=grow(ctx,mode==7?0:65);
    heap->rc->allocator.hooks=original;
    return 0;
}
int main(int argc,char **argv) {
    if(argc!=6)return 2;mode=atoi(argv[5]);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 3;}
    grow=dlsym(library,argv[2]);wide=dlsym(library,argv[3]);written=dlsym(library,argv[4]);
    import_descriptor=dlsym(library,"myl_rc_descriptor_import");allocate=dlsym(library,"myl_native_heap_alloc");
    release=dlsym(library,"myl_rc_owner_release");edge_release=dlsym(library,"myl_rc_edge_release");
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!grow||!wide||!written||!import_descriptor||!allocate||!release||!edge_release||!initialize||!execute)return 4;
    MylQbeResult result={0};
    int status=execute(entry,mode==10?1:mode==11?100:100000,64,0,NULL,initialize,&result);
    printf("mode=%d status=%d observed=%d length=%zu hooks=%d injected=%d bad=%d result=%llu code=%s steps=%llu\n",mode,status,observed,observed_length,hooks,injected,bad,(unsigned long long)answer,result.code?result.code:"none",(unsigned long long)result.steps);
    int trap=mode==3||mode==4||mode>=8;
    uint64_t expected=mode==5?72:mode==6?130:mode==7?0:65;
    int failed=bad||(trap?!status:status||answer!=expected);
    if(mode==1)failed|=observed!=1;
    if(mode==2)failed|=observed!=1||observed_length!=8;
    if(mode==7)failed|=injected||observed;
    dlclose(library);return failed;
}
