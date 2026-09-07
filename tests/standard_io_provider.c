/* Matching deterministic partial-transfer fixture for the source standard I/O tests. */
#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static size_t position, length, reads, writes, acquired, released, completions;
static unsigned live;
static uint8_t output[256], metadata[10];
static const uint8_t listing[] = {1,1,4,0,'d','a','t','a',2,6,0,'n','e','s','t','e','d',3,4,0,'l','i','n','k',1,8,0,'o','d','d','\\','n','a','m','e'};
static const uint8_t *input;
static size_t input_length;
static int setting(const char *name) { const char *s=getenv(name); return s?atoi(s):0; }
static MylangResourceResult acquire(void *unused,const uint8_t *request,size_t n,unsigned permissions) {
    (void)unused;
    if (live || n<2 || permissions!=(request[0]=='w'?6u:5u)) return (MylangResourceResult){MYLANG_PROVIDER_DENIED,0};
    const char *custom=getenv("IO_INPUT"); input=(const uint8_t *)(custom?custom:"abc"); input_length=strlen((const char *)input);
    if (n==2 && !memcmp(request,"l:",2)) {
        input=listing;input_length=sizeof(listing)-(setting("IO_LIST_BAD")?1u:0u);
    } else if ((n==2 && !memcmp(request,"m:",2)) || (n==6 && (!memcmp(request,"m:data",6) || !memcmp(request,"m:link",6)))) {
        memset(metadata,0,sizeof(metadata));metadata[0]=setting("IO_META_BAD")?2:1;
        metadata[1]=n==2?2:(!memcmp(request,"m:link",6)?3:1);metadata[2]=n==2?0:3;
        input=metadata;input_length=sizeof(metadata);
    } else if (n!=6 || (memcmp(request,"r:data",6) && memcmp(request,"w:data",6))) {
        return (MylangResourceResult){MYLANG_PROVIDER_DENIED,0};
    }
    position=0;
    live=1; ++acquired;
    return (MylangResourceResult){MYLANG_PROVIDER_OK,0};
}
static void release(void *unused,uint64_t id) {
    (void)unused; (void)id;
    if (!live) abort(); live=0; ++released;
}
static MylangProviderStatus complete(void *unused,uint64_t id) { ++completions;if((size_t)setting("IO_CLOSE_FAIL")==completions)return MYLANG_PROVIDER_FAILED;release(unused,id);return MYLANG_PROVIDER_OK; }
static MylangResourceRead read_bytes(void *unused,uint64_t id,uint8_t *bytes,size_t capacity) {
    (void)unused; (void)id;
    ++reads;
    if ((size_t)setting("IO_READ_FAIL")==reads) {
        if (setting("IO_STALL")) return (MylangResourceRead){MYLANG_PROVIDER_OK,0,0};
        return (MylangResourceRead){MYLANG_PROVIDER_FAILED,0,0};
    }
    size_t n=input_length-position;if(n>capacity)n=capacity;if(n>2)n=2;
    memcpy(bytes,input+position,n);position+=n;
    return (MylangResourceRead){MYLANG_PROVIDER_OK,n,position==input_length};
}
static MylangResourceWrite write_bytes(void *unused,uint64_t id,const uint8_t *bytes,size_t size) {
    (void)unused; (void)id;
    ++writes;
    if ((size_t)setting("IO_WRITE_FAIL")==writes) {
        if(setting("IO_STALL"))return (MylangResourceWrite){MYLANG_PROVIDER_OK,0};
        return (MylangResourceWrite){MYLANG_PROVIDER_FAILED,0};
    }
    size_t n=size>2?2:size;if(n>sizeof(output)-length)n=sizeof(output)-length;
    memcpy(output+length,bytes,n);length+=n;
    return (MylangResourceWrite){MYLANG_PROVIDER_OK,n};
}
static void report(void) {
    fprintf(stderr,"io-live: %u acquired: %zu released: %zu\n",live,acquired,released);
    fprintf(stderr,"io-calls: %zu %zu output: %.*s\n",reads,writes,(int)length,output);
    if(live || acquired!=released)abort();
}
MylangNativeProviders mylang_native_providers(void) {
    atexit(report);
    return (MylangNativeProviders){.filesystem={.permissions=7,.acquire=acquire,.complete=complete,.release=release,.read=read_bytes,.write=write_bytes}};
}
