#include "qbe_runtime.h"
#include "native_providers.h"
#include <stdlib.h>
#include <string.h>
typedef struct Resource {
    myl_native_resource base;
    MylQbeContext *context;
    struct Resource *previous,*next;
    uint64_t handle;
    unsigned kind,permissions;
} Resource;
static const MylangResourceProvider empty={0};
static const MylangResourceProvider *provider(MylQbeContext *ctx,unsigned kind) {
    (void)mylang_host_charge;
    if (!ctx->providers) return &empty;
    return kind ? &ctx->providers->network:&ctx->providers->filesystem;
}
static int status(MylQbeContext *ctx,MylangProviderStatus value) {
    if (value==MYLANG_PROVIDER_OUT_OF_MEMORY) myl_qbe_fail_allocation(ctx);
    else if (value<MYLANG_PROVIDER_OK || value>MYLANG_PROVIDER_FAILED) myl_qbe_fail(ctx,"InvalidProvider");
    return myl_qbe_failed(ctx) ? -1:(int)value;
}
static void unlink_resource(Resource *resource) {
    MylQbeContext *ctx=resource->context;
    if (resource->previous) resource->previous->next=resource->next;
    if (resource->next) resource->next->previous=resource->previous;
    else ctx->resource_tails[resource->kind]=resource->previous;
    ctx->resource_live[resource->kind]--;
}
static void drop(myl_native_resource *value) {
    Resource *resource=(Resource *)value;
    const MylangResourceProvider *p=provider(resource->context,resource->kind);
    p->release(p->context,resource->handle);
    unlink_resource(resource);
    free(resource);
}
static void cleanup(void *context) {
    MylQbeContext *ctx=context;
    for (unsigned kind=2;kind;kind--) while (ctx->resource_tails[kind-1]) drop(ctx->resource_tails[kind-1]);
}
uint64_t myl_qbe_grant_resource(void *context,unsigned kind) {
    MylQbeContext *ctx=context;
    if (kind>1) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    const MylangResourceProvider *p=provider(ctx,kind);
    if (p->permissions & ~7u) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (!p->acquire || !p->complete || !p->release) { myl_qbe_fail(ctx,"CapabilityUnavailable");return 0; }
    return (uint64_t)(INT64_C(-16)-(int64_t)(kind*8+p->permissions));
}
uint64_t myl_qbe_grant_resource_checked(void *context,unsigned kind,const char *flag) {
    MylQbeContext *ctx=context;
    if (kind>1) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    const MylangResourceProvider *p=provider(ctx,kind);
    if (p->permissions & ~7u) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (!p->acquire || !p->complete || !p->release) { myl_qbe_fail_missing_capability(ctx,flag);return 0; }
    return (uint64_t)(INT64_C(-16)-(int64_t)(kind*8+p->permissions));
}
static int authority(MylQbeContext *ctx,uint64_t bits,unsigned *kind,unsigned *permissions) {
    int64_t value;memcpy(&value,&bits,8);
    if (value < -31 || value > -16) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    unsigned encoded=(unsigned)(-16-value);
    *permissions=encoded&7;*kind=encoded>>3;
    return 1;
}
uint64_t myl_qbe_restrict_resource(void *context,uint64_t bits,unsigned mask) {
    unsigned kind,permissions;
    if (!authority(context,bits,&kind,&permissions)) return 0;
    return (uint64_t)(INT64_C(-16)-(int64_t)(kind*8+(permissions&mask)));
}
int myl_qbe_resource_new(void *context,uint64_t bits,unsigned kind,const unsigned char *request,size_t length,myl_native_resource **output) {
    MylQbeContext *ctx=context;
    unsigned selected,permissions;
    *output=NULL;
    if (!authority(ctx,bits,&selected,&permissions)) return -1;
    if (selected!=kind) { myl_qbe_fail(ctx,"InvalidCapability");return -1; }
    const MylangResourceProvider *p=provider(ctx,kind);
    if (ctx->resource_live[kind]>=1024) return 4;
    if (!p->acquire || !p->release || !p->complete) return 1;
    Resource *resource=calloc(1,sizeof *resource);
    unsigned char *bytes=malloc(length?length:1);
    if (!resource || !bytes) { free(resource);free(bytes);myl_qbe_fail_allocation(ctx);return -1; }
    if (length) memcpy(bytes,request,length);
    MylangResourceResult result=p->acquire(p->context,bytes,length,permissions);
    free(bytes);
    int code=status(ctx,result.status);
    if (code) { free(resource);return code; }
    resource->base.drop=drop;resource->context=ctx;resource->kind=kind;
    resource->permissions=permissions;resource->handle=result.handle;
    resource->previous=ctx->resource_tails[kind];
    if (resource->previous) resource->previous->next=resource;
    ctx->resource_tails[kind]=resource;ctx->resource_live[kind]++;
    ctx->cleanup=cleanup;
    *output=&resource->base;
    return 0;
}
int myl_qbe_resource_complete(void *context,myl_native_resource *value) {
    Resource *resource=(Resource *)value;
    if (!resource || resource->context!=context) { myl_qbe_fail(context,"InvalidOwner");return -1; }
    if (!(resource->permissions&4)) return 2;
    const MylangResourceProvider *p=provider(context,resource->kind);
    int code=status(context,p->complete(p->context,resource->handle));
    if (!code) { unlink_resource(resource);free(resource); }
    return code;
}
int myl_qbe_resource_read(void *context,myl_native_resource *value,unsigned char *output,size_t capacity,size_t *length,int *eof) {
    Resource *resource=(Resource *)value;
    *length=0;*eof=0;
    if (!resource || resource->context!=context) { myl_qbe_fail(context,"InvalidOwner");return -1; }
    if (!(resource->permissions&1)) return 2;
    const MylangResourceProvider *p=provider(context,resource->kind);
    if (!p->read) return 1;
    unsigned char *bytes=malloc(capacity?capacity:1);
    if (!bytes) { myl_qbe_fail_allocation(context);return -1; }
    MylangResourceRead result=p->read(p->context,resource->handle,bytes,capacity);
    int code=status(context,result.status);
    if (!code && (result.length>capacity || (result.eof!=0 && result.eof!=1))) { myl_qbe_fail(context,"InvalidProvider");code=-1; }
    if (!code) {
        if (result.length) memcpy(output,bytes,result.length);
        *length=result.length;*eof=result.eof;
    }
    free(bytes);return code;
}
int myl_qbe_resource_write(void *context,myl_native_resource *value,const unsigned char *input,size_t length,size_t *written) {
    Resource *resource=(Resource *)value;
    *written=0;
    if (!resource || resource->context!=context) { myl_qbe_fail(context,"InvalidOwner");return -1; }
    if (!(resource->permissions&2)) return 2;
    const MylangResourceProvider *p=provider(context,resource->kind);
    if (!p->write) return 1;
    unsigned char *bytes=malloc(length?length:1);
    if (!bytes) { myl_qbe_fail_allocation(context);return -1; }
    if (length) memcpy(bytes,input,length);
    MylangResourceWrite result=p->write(p->context,resource->handle,bytes,length);
    free(bytes);
    int code=status(context,result.status);
    if (!code && result.length>length) { myl_qbe_fail(context,"InvalidProvider");return -1; }
    if (!code) *written=result.length;
    return code;
}
