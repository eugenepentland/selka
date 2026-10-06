/* Deterministic copied network fixture; it never performs a network read. */
#include "../../../../src/native_providers.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned acquired,completed,released,live,attempts;
static MylangResourceResult acquire(void *context,const uint8_t *request,size_t length,unsigned rights){
    (void)context;
    if(length!=14||memcmp(request,"127.0.0.1:1234",14)||rights!=7)return (MylangResourceResult){MYLANG_PROVIDER_DENIED,0};
    ++acquired;++live;return (MylangResourceResult){MYLANG_PROVIDER_OK,acquired};
}
static MylangProviderStatus complete(void *context,uint64_t handle){
    (void)context;
    if(getenv("MYL_FIXTURE_STACK")){++completed;--live;return MYLANG_PROVIDER_OK;}
    if(handle!=3)return MYLANG_PROVIDER_FAILED;
    if(++attempts==1)return MYLANG_PROVIDER_FAILED;
    ++completed;--live;return MYLANG_PROVIDER_OK;
}
static void release(void *context,uint64_t handle){
    (void)context;(void)handle;++released;--live;const char *path=getenv("MYL_FIXTURE_TRACE");
    if(path){FILE *file=fopen(path,"a");if(file){fprintf(file,"release=%u live=%u\n",released,live);fclose(file);}}
}
static MylangResourceRead read_bytes(void *context,uint64_t handle,uint8_t *bytes,size_t capacity){
    (void)context;if(handle!=1||capacity!=4)return (MylangResourceRead){MYLANG_PROVIDER_FAILED,0,0};
    const char *bad=getenv("MYL_FIXTURE_BAD_READ");
    if(bad&&!strcmp(bad,"oversize"))return (MylangResourceRead){MYLANG_PROVIDER_OK,capacity+1,0};
    if(bad&&!strcmp(bad,"eof"))return (MylangResourceRead){MYLANG_PROVIDER_OK,0,2};
    if(bad&&!strcmp(bad,"error-fields"))return (MylangResourceRead){MYLANG_PROVIDER_FAILED,(size_t)-1,99};
    if(bad&&!strcmp(bad,"status"))return (MylangResourceRead){(MylangProviderStatus)99,0,0};
    memcpy(bytes,"ab",2);return (MylangResourceRead){MYLANG_PROVIDER_OK,2,1};
}
static MylangResourceWrite write_bytes(void *context,uint64_t handle,const uint8_t *bytes,size_t length){
    (void)context;if(handle!=2||length!=2||memcmp(bytes,"cd",2))return (MylangResourceWrite){MYLANG_PROVIDER_FAILED,0};
    return (MylangResourceWrite){MYLANG_PROVIDER_OK,2};
}
int64_t trap_flag(void){return 0;}
int64_t final_status(void){if(getenv("MYL_FIXTURE_STACK"))return acquired==301&&completed==301&&released==0&&live==0?0:9;return acquired==3&&completed==1&&released==2&&live==0&&attempts==2?0:9;}
MylangNativeProviders mylang_native_providers_v7(void){
    MylangNativeProviders providers={0};
    providers.network=(MylangResourceProvider){NULL,7,acquire,complete,release,read_bytes,write_bytes};return providers;
}
