#include "qbe_runtime.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t (*make)(void *), (*probe)(void *, uint64_t);
static void (*enter)(void *,MylQbeRcFrame *,MylQbeRcSlot *,size_t);
static myl_native_type pointer_type = {.size = sizeof(void *)};
static MylQbeRcFrame frame;
static MylQbeRcSlot slot;
static uint32_t initialized;
static void *rows;
static unsigned made;
static uint64_t entry(void *context) {
    rows = (void *)make(context);
    initialized = 1;
    slot = (MylQbeRcSlot){&pointer_type, &rows, &initialized, MYL_QBE_RC_CONSTRUCTION};
    enter(context, &frame, &slot, 1);
    made = 1;
    MylQbeContext *ctx = context;
    ctx->heap.limit = ctx->heap.bytes;
    return probe(context, (uint64_t)rows);
}
int main(int argc,char **argv) {
    if(argc!=4)return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 2;}
    make=dlsym(library,argv[2]);probe=dlsym(library,argv[3]);
    enter=dlsym(library,"myl_qbe_rc_frame_enter");
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!make||!probe||!initialize||!execute||!enter)return 3;
    MylQbeResult result={0};
    int status=execute(entry,10000,64,0,NULL,initialize,&result);
    printf("%d %s made=%u guard=%u rows=%p\n",status,result.code?result.code:"ok",made,initialized,rows);
    int correct=status==1&&result.code&&!strcmp(result.code,"R_MEMORY_BUDGET")&&made==1&&initialized==0&&rows==NULL;
    dlclose(library);return correct?0:4;
}
