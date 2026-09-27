#include "qbe_runtime.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
static uint64_t (*update)(void *,uint64_t);
static myl_rc_status (*import_descriptor)(myl_native_heap *,const myl_rc_descriptor *);
static void *(*allocate)(myl_native_heap *,const myl_native_type *,size_t);
static void (*release)(myl_native_heap *,void *);
static void *context;
static int phase, observed, bad;
static uint64_t answer;
static const myl_native_type type={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static void finalized(myl_native_heap *heap,void *payload) {
    if (*(uint64_t *)payload) { observed++; if(phase!=2)bad=1; return; }
    phase=1;
    uint64_t *queued=allocate(heap,&type,1);
    if(!queued){bad=2;return;}
    *queued=1;release(heap,queued);
    if(observed){bad=3;return;}
    answer=update(context,30);
    if(observed){bad=4;return;}
    phase=2;
}
static uint64_t entry(void *ctx) {
    context=ctx;
    static const myl_rc_shape shape={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&type,.shape=&shape,.finalize=finalized};
    myl_native_heap *heap=&((MylQbeContext *)ctx)->heap;
    if(import_descriptor(heap,&descriptor)!=MYL_RC_OK){bad=5;return 1;}
    uint64_t *first=allocate(heap,&type,1);
    if(!first){bad=6;return 1;}
    *first=0;release(heap,first);
    return 0;
}
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 3;}
    update=dlsym(library,argv[2]);
    import_descriptor=dlsym(library,"myl_rc_descriptor_import");
    allocate=dlsym(library,"myl_native_heap_alloc");release=dlsym(library,"myl_rc_owner_release");
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!update||!import_descriptor||!allocate||!release||!initialize||!execute)return 4;
    MylQbeResult result={0};
    int status=execute(entry,100000,64,0,NULL,initialize,&result);
    printf("status=%d phase=%d observed=%d bad=%d result=%llu\n",status,phase,observed,bad,(unsigned long long)answer);
    int failed=status||bad||phase!=2||observed!=1||answer!=10;
    dlclose(library);return failed;
}
