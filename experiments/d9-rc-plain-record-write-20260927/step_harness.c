#include "qbe_runtime.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t (*update)(void *,uint64_t,uint64_t);
static struct { void *items; int64_t count, frames; } state;
static uint64_t entry(void *ctx) { return update(ctx,(uint64_t)&state,1); }
int main(int argc,char **argv) {
    if(argc!=4)return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 2;}
    update=dlsym(library,argv[2]);
    void (*initialize)(void *)=dlsym(library,"myl_qbe_host_begin");
    int (*execute)(uint64_t(*)(void*),uint64_t,uint64_t,int,const struct MylangNativeProvidersTag *,void(*)(void*),MylQbeResult *)=dlsym(library,"mylang_qbe_execute_config");
    if(!update||!initialize||!execute)return 3;
    for(unsigned budget=17;budget<=20;budget++) {
        state.items=NULL;state.count=41;state.frames=91;
        MylQbeResult result={0};
        int status=execute(entry,budget,64,1,NULL,initialize,&result);
        printf("%u %d %llu %s %lld %lld\n",budget,status,(unsigned long long)result.steps,result.code?result.code:"ok",(long long)state.count,(long long)state.frames);
        if(status!=1||strcmp(result.code,"R_STEP_LIMIT")||state.count!=(budget<(unsigned)atoi(argv[3])?41:42)||state.frames!=91)return 4;
    }
    dlclose(library);return 0;
}
