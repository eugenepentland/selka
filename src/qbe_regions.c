#include "qbe_runtime.h"
#include <string.h>
static myl_native_region *region(MylQbeContext *ctx,uint64_t authority) {
    if (authority==1) return NULL;
    for (size_t i=0;i<256;i++) if (ctx->regions[i].identity && ctx->regions[i].identity==authority) return &ctx->regions[i];
    myl_qbe_fail_capability(ctx);
    return NULL;
}
uint64_t myl_qbe_region_begin(void *context,uint64_t authority) {
    MylQbeContext *ctx=context;
    myl_native_region *parent=region(ctx,authority);
    if (myl_qbe_failed(ctx)) return 0;
    if (!ctx->next_region_identity) ctx->next_region_identity=2;
    if (ctx->next_region_identity==UINT64_MAX) { myl_qbe_fail_identity(ctx);return 0; }
    for (size_t i=0;i<256;i++) if (!ctx->regions[i].identity) {
        myl_native_region *child=&ctx->regions[i];
        child->identity=ctx->next_region_identity++;
        child->parent=parent;
        if (parent) parent->children++;
        return child->identity;
    }
    myl_qbe_fail_region_limit(ctx);
    return 0;
}
void myl_qbe_region_end(void *context,uint64_t identity) {
    MylQbeContext *ctx=context;
    myl_native_region *owner=region(ctx,identity);
    if (myl_qbe_failed(ctx)) return;
    if (!owner) { myl_qbe_fail_capability(ctx);return; }
    if (owner->users || owner->children) { myl_qbe_fail_region_in_use(ctx);return; }
    if (owner->parent) owner->parent->children--;
    memset(owner,0,sizeof *owner);
}
int myl_qbe_owned_new(void *context,const myl_native_type *element,uint64_t authority,int64_t capacity,size_t limit,myl_native_owned_buffer **output) {
    MylQbeContext *ctx=context;
    *output=NULL;
    myl_native_region *owner=region(ctx,authority);
    if (myl_qbe_failed(ctx)) return -1;
    int status=myl_native_owned_new(&ctx->heap,element,capacity,limit,output);
    if (!status) { (*output)->region=owner;if (owner) owner->users++; }
    else if (status<0) myl_qbe_fail_allocation(ctx);
    return status;
}
int myl_qbe_owned_reserve(void *context,myl_native_owned_buffer *buffer,uint64_t authority,int64_t capacity,size_t limit) {
    MylQbeContext *ctx=context;
    myl_native_region *owner=region(ctx,authority);
    if (myl_qbe_failed(ctx)) return -1;
    if (owner!=buffer->region) { myl_qbe_fail_capability(ctx);return -1; }
    int status=myl_native_owned_reserve(&ctx->heap,buffer,capacity,limit);
    if (status<0) myl_qbe_fail_allocation(ctx);
    return status;
}
int myl_qbe_pool_new(void *context,const myl_native_type *element,uint64_t authority,int64_t capacity,myl_native_pool **output) {
    MylQbeContext *ctx=context;
    *output=NULL;
    myl_native_region *owner=region(ctx,authority);
    if (myl_qbe_failed(ctx)) return -1;
    int status=myl_native_pool_new(&ctx->heap,element,capacity,output);
    if (!status) { (*output)->region=owner;if (owner) owner->users++; }
    else if (status<0) myl_qbe_fail_allocation(ctx);
    return status;
}

int myl_qbe_region_reset(void *context,uint64_t identity) {
    MylQbeContext *ctx=context;
    for (size_t i=0;i<256;i++) if (ctx->regions[i].identity && ctx->regions[i].identity==identity) {
        const myl_native_region *owner=&ctx->regions[i];
        if (owner->children) return 2;
        return owner->users ? 1:0;
    }
    return 3;
}
