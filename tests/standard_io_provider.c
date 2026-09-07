/* Matching deterministic partial-transfer fixture for the source standard I/O tests. */
#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static size_t position, length, reads, writes, acquired, released;
static unsigned live;
static uint8_t output[256];
static int setting(const char *name) { const char *s=getenv(name); return s?atoi(s):0; }
static MylangResourceResult acquire(void *unused,const uint8_t *request,size_t n,unsigned permissions) {
    (void)unused; (void)permissions;
    if (live || n!=6 || (memcmp(request,"r:data",6) && memcmp(request,"w:data",6)))
        return (MylangResourceResult){MYLANG_PROVIDER_DENIED,0};
    live=1; ++acquired;
    return (MylangResourceResult){MYLANG_PROVIDER_OK,0};
}
static void release(void *unused,uint64_t id) {
    (void)unused; (void)id;
    if (!live) abort(); live=0; ++released;
}
static MylangProviderStatus complete(void *unused,uint64_t id) { release(unused,id);return MYLANG_PROVIDER_OK; }
static MylangResourceRead read_bytes(void *unused,uint64_t id,uint8_t *bytes,size_t capacity) {
    (void)unused; (void)id;
    ++reads;
    if ((size_t)setting("IO_READ_FAIL")==reads) {
        if (setting("IO_STALL")) return (MylangResourceRead){MYLANG_PROVIDER_OK,0,0};
        return (MylangResourceRead){MYLANG_PROVIDER_FAILED,0,0};
    }
    size_t n=3-position;if(n>capacity)n=capacity;if(n>2)n=2;
    memcpy(bytes,"abc"+position,n);position+=n;
    return (MylangResourceRead){MYLANG_PROVIDER_OK,n,position==3};
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
