#include "qbe_runtime.h"
#include "native_providers.h"
#include <assert.h>
#include <string.h>
static int reads,releases,completes;
static uint64_t released[8];
static MylangClockResult clock_now(void *ctx) { (void)ctx;reads++;return (MylangClockResult){MYLANG_PROVIDER_OK,-42}; }
static MylangResourceResult acquire(void *ctx,const uint8_t *bytes,size_t count,unsigned permissions) {
    (void)ctx;assert(count==1 && *bytes==7 && permissions==7);
    return (MylangResourceResult){MYLANG_PROVIDER_OK,(uint64_t)++reads};
}
static MylangProviderStatus complete(void *ctx,uint64_t handle) { (void)ctx;(void)handle;return ++completes==1?MYLANG_PROVIDER_FAILED:MYLANG_PROVIDER_OK; }
static void release(void *ctx,uint64_t handle) { (void)ctx;released[releases++]=handle; }
static MylangResourceRead read_bytes(void *ctx,uint64_t handle,uint8_t *bytes,size_t capacity) {
    (void)ctx;(void)handle;assert(capacity==2);bytes[0]=42;return (MylangResourceRead){MYLANG_PROVIDER_OK,1,1};
}
static uint64_t entry(void *context) {
    (void)mylang_host_charge;
    uint64_t token=myl_qbe_grant_external(context,0),number=0;
    assert(myl_qbe_external_read(context,token,0,&number)==0 && number==(uint64_t)INT64_C(-42));
    token=myl_qbe_grant_resource(context,0);
    unsigned char request=7,output[2]={99,99};size_t length=0;int eof=0;
    myl_native_resource *one=NULL,*two=NULL;
    assert(myl_qbe_resource_new(context,token,0,&request,1,&one)==0);
    assert(myl_qbe_resource_read(context,one,output,2,&length,&eof)==0);
    assert(length==1 && eof==1 && output[0]==42 && output[1]==99);
    assert(myl_qbe_resource_complete(context,one)==3);
    assert(myl_qbe_resource_complete(context,one)==0 && releases==0);
    assert(myl_qbe_resource_new(context,token,0,&request,1,&one)==0);
    assert(myl_qbe_resource_new(context,token,0,&request,1,&two)==0);
    myl_qbe_fail(context,"R_OVERFLOW");
    return 0;
}
int main(void) {
    MylangNativeProviders providers={.clock_now=clock_now,.filesystem={.permissions=7,.acquire=acquire,.complete=complete,.release=release,.read=read_bytes}};
    MylQbeResult result;
    assert(mylang_qbe_execute_providers(entry,100,10,1,&providers,&result)==1);
    assert(!strcmp(result.code,"R_OVERFLOW"));
    assert(releases==2 && released[0]>released[1]);
    MylQbeContext context={0};
    assert(myl_qbe_grant_external(&context,0)==0 && !strcmp(context.trap,"CapabilityUnavailable"));
}
