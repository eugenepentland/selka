#include "qbe_runtime.h"
#include "native_rc_internal.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static void *(*seed)(void *);
static uint64_t (*visit)(void *,void *);
static myl_rc_status (*import_descriptor)(myl_native_heap *,const myl_rc_descriptor *);
static void *(*allocate)(myl_native_heap *,const myl_native_type *,size_t);
static void (*release)(myl_native_heap *,void *);
static void *context,*items;
static int mode,observed,bad,inside;
static uint64_t answer;
static const myl_native_type type={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static void finalized(myl_native_heap *heap,void *payload) {
    if(*(uint64_t *)payload==2){observed++;return;}
    uint64_t *queued=allocate(heap,&type,1);
    if(!queued){bad=1;return;} *queued=2; release(heap,queued);
    if(observed)bad=2;
    inside=1; answer=visit(context,items); inside=0;
    if(observed)bad=3;
}
static void cleanup(void *ctx) {
    if(items)release(&((MylQbeContext *)ctx)->heap,items);
    items=NULL;
}
static uint64_t entry(void *ctx) {
    context=ctx; MylQbeContext *state=ctx; myl_native_heap *heap=&state->heap;
    static const myl_rc_shape shape={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&type,.shape=&shape,.finalize=finalized};
    state->adapter_cleanup=cleanup;
    items=seed(ctx); if(!items){bad=4;return 0;}
    if(import_descriptor(heap,&descriptor)!=MYL_RC_OK){bad=5;return 0;}
    uint64_t *first=allocate(heap,&type,1);if(!first){bad=6;return 0;}
    *first=mode==1?1:2;release(heap,first);
    if(observed!=1)bad=7;
    if(mode==0)answer=visit(ctx,items);
    return 0;
}
int main(int argc,char **argv) {
    if(argc!=5)return 2; mode=atoi(argv[4]);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!library){fprintf(stderr,"%s\n",dlerror());return 3;}
    seed=dlsym(library,argv[2]); visit=dlsym(library,argv[3]);
    import_descriptor=dlsym(library,"myl_rc_descriptor_import");allocate=dlsym(library,"myl_native_heap_alloc");release=dlsym(library,"myl_rc_owner_release");
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!seed||!visit||!import_descriptor||!allocate||!release||!initialize||!execute)return 4;
    MylQbeResult result={0};int status=execute(entry,MYL_QBE_UNBOUNDED,MYL_QBE_UNBOUNDED,0,NULL,initialize,&result);
    printf("mode=%d status=%d observed=%d inside=%d bad=%d answer=%llu\n",mode,status,observed,inside,bad,(unsigned long long)answer);
    int failed=status||observed!=1||inside||bad||answer!=114;dlclose(library);return failed;
}
