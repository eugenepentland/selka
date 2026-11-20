/* Independent ABI5 probe. All counts are artificial states on actual allocated
 * objects; each success checks production emitted pin/end code, not copied IL.
 * No timing. Private renamed native helpers prove which branch ran. */
#include "qbe_runtime.h"
#include "native_rc_internal.h"
#include "native_rc_alloc.h"
#include "native_rc_collections.h"
#include "native_collections.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>

_Static_assert(MYL_RC_ABI_VERSION == 5, "probe must run only frozen ABI5");
_Static_assert(sizeof(myl_rc_object) == 32, "wide RC prefix");
_Static_assert(sizeof(((myl_rc_object *)0)->owners) == 8, "u64 owner count");
_Static_assert(sizeof(((myl_rc_object *)0)->holds) == 8, "u64 hold count");
_Static_assert(sizeof(myl_native_object) == 16, "common immortal/GC/arena prefix");
_Static_assert(offsetof(myl_rc_object, holds) == 8, "wide holds offset");
_Static_assert(offsetof(myl_rc_object, common) == 16, "common header invariant");

extern int review_scope_pin(void *, myl_native_heap *, myl_rc_scope *, void *);
extern void review_scope_end(void *, myl_native_heap *, myl_rc_scope *);
extern int review_real_scope_pin(void *, myl_rc_scope *, void *);
extern void review_real_scope_end(void *, myl_rc_scope *);
static unsigned slow_pin, slow_end;
int myl_qbe_rc_scope_pin(void *ctx, myl_rc_scope *scope, void *payload) {
    ++slow_pin;
    return review_real_scope_pin(ctx, scope, payload);
}
void myl_qbe_rc_scope_end(void *ctx, myl_rc_scope *scope) {
    ++slow_end;
    review_real_scope_end(ctx, scope);
}
static const myl_native_type scalar = {.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static myl_rc_object *header(void *value) { return (myl_rc_object *)value-1; }
static void start(MylQbeContext *ctx) {
    memset(ctx,0,sizeof *ctx);
    myl_native_heap_init(&ctx->heap,64u<<20);
    if (!myl_rc_enabled(&ctx->heap)) assert(myl_rc_storage_init(&ctx->heap)==MYL_RC_OK);
    assert(myl_rc_list_require(&ctx->heap)==MYL_RC_OK);
    slow_pin=slow_end=0;
}
static void finish(MylQbeContext *ctx) {
    assert(!ctx->heap.rc->scopes && !ctx->heap.rc->dead.head && !ctx->heap.objects_live);
    myl_native_heap_destroy(&ctx->heap);
    assert(!ctx->heap.bytes);
}
static void prime(MylQbeContext *ctx,myl_native_list *value) {
    myl_rc_scope scope={0};
    myl_rc_scope_begin(&ctx->heap,&scope);
    assert(myl_rc_scope_pin(&scope,value)==MYL_RC_OK);
    myl_rc_scope_end(&scope);
    assert(ctx->heap.rc->spare.count>0);
}
static void success_case(const char *name,uint64_t owners,uint64_t holds,
                         uint64_t backing_owners,uint64_t backing_holds,int backed,int pinned) {
    MylQbeContext ctx;
    start(&ctx);
    myl_native_list *value=myl_native_list_new(&ctx.heap,&scalar,backed?1:0);
    assert(value);
    prime(&ctx,value);
    myl_rc_object *object=header(value),*backing=backed?header(value->storage):NULL;
    object->owners=owners;
    object->holds=holds;
    if (backing) backing->owners=backing_owners,backing->holds=backing_holds;
    if (pinned) object->common.mark|=MYL_NATIVE_OBJECT_PINNED;
    const uintptr_t mark=object->common.mark;
    const size_t bytes=ctx.heap.bytes, metadata=ctx.heap.rc->metadata.bytes,spares=ctx.heap.rc->spare.count;
    myl_rc_scope scope={0};
    assert(review_scope_pin(&ctx,&ctx.heap,&scope,value));
    assert(!ctx.trap && slow_pin==0);
    assert(scope.active && scope.heap==&ctx.heap && ctx.heap.rc->scopes==&scope && scope.journal);
    assert(object->owners==owners && object->holds==holds+1);
    assert((object->common.mark&MYL_NATIVE_OBJECT_PINNED)!=0);
    if (backing) assert(backing->owners==backing_owners && backing->holds==backing_holds+1);
    assert(ctx.heap.bytes==bytes+40 && ctx.heap.rc->metadata.bytes==metadata+40 && ctx.heap.rc->spare.count==spares-1);
    review_scope_end(&ctx,&ctx.heap,&scope);
    const unsigned expected_slow_end=0;
    printf("CHECK %s slow-end=%u expected=%u O=%"PRIu64" H=%"PRIu64" active=%u journal=%p scopes=%p\n",name,slow_end,expected_slow_end,object->owners,object->holds,scope.active,scope.journal,(void *)ctx.heap.rc->scopes);
    assert(slow_end==expected_slow_end && !ctx.trap && !scope.active && !scope.journal && !ctx.heap.rc->scopes);
    assert(object->owners==owners && object->holds==holds && object->common.mark==mark);
    if (backing) assert(backing->owners==backing_owners && backing->holds==backing_holds);
    assert(ctx.heap.bytes==bytes && ctx.heap.rc->metadata.bytes==metadata && ctx.heap.rc->spare.count==spares);
    /* Normalize fabricated tokens before ordinary complete release. */
    object->owners=1; object->holds=0; object->common.mark&=~MYL_NATIVE_OBJECT_PINNED;
    if (backing) backing->owners=1,backing->holds=0;
    myl_rc_owner_release(&ctx.heap,value);
    finish(&ctx);
    printf("PASS success %s O=%"PRIu64" H=%"PRIu64" fast-pin=1 fast-end=%u\n",name,owners,holds,slow_end==0);
}
static void refusal_case(const char *name,int backing_full,int pre_pinned) {
    MylQbeContext ctx;
    start(&ctx);
    myl_native_list *value=myl_native_list_new(&ctx.heap,&scalar,1);
    assert(value && value->storage);
    prime(&ctx,value);
    myl_rc_object *object=header(value),*backing=header(value->storage);
    object->owners=(UINT64_C(1)<<32)+13;
    object->holds=backing_full?(UINT64_C(1)<<32)+7:UINT64_MAX;
    backing->owners=(UINT64_C(1)<<32)+19;
    backing->holds=backing_full?UINT64_MAX:(UINT64_C(1)<<32)+11;
    if (pre_pinned) object->common.mark|=MYL_NATIVE_OBJECT_PINNED;
    const myl_rc_object previous=*object,previous_backing=*backing;
    const size_t bytes=ctx.heap.bytes,metadata=ctx.heap.rc->metadata.bytes,spares=ctx.heap.rc->spare.count;
    myl_rc_scope scope={0};
    assert(!review_scope_pin(&ctx,&ctx.heap,&scope,value));
    assert(slow_pin==1 && ctx.trap && !strcmp(ctx.trap,"R_REFERENCE_COUNT_LIMIT"));
    assert(scope.active && !scope.journal && ctx.heap.rc->scopes==&scope);
    assert(!memcmp(object,&previous,sizeof previous) && !memcmp(backing,&previous_backing,sizeof previous_backing));
    assert(ctx.heap.bytes==bytes && ctx.heap.rc->metadata.bytes==metadata && ctx.heap.rc->spare.count==spares);
    review_scope_end(&ctx,&ctx.heap,&scope);
    assert(slow_end==0 && !scope.active && !scope.journal && !ctx.heap.rc->scopes);
    assert(!memcmp(object,&previous,sizeof previous) && !memcmp(backing,&previous_backing,sizeof previous_backing));
    object->owners=1; object->holds=0; object->common.mark&=~MYL_NATIVE_OBJECT_PINNED;
    backing->owners=1; backing->holds=0;
    myl_rc_owner_release(&ctx.heap,value);
    finish(&ctx);
    printf("PASS refusal %s rollback=counts,pins,journal,budget,spares\n",name);
}
static void retiring_case(void) {
    MylQbeContext ctx;
    start(&ctx);
    myl_native_list *value=myl_native_list_new(&ctx.heap,&scalar,1);
    assert(value && value->storage);
    prime(&ctx,value);
    const size_t live=ctx.heap.objects_live;
    myl_rc_scope scope={0};
    assert(review_scope_pin(&ctx,&ctx.heap,&scope,value));
    myl_rc_owner_release(&ctx.heap,value);
    assert(header(value)->owners==0 && header(value)->holds==1);
    assert(ctx.heap.objects_live==live);
    review_scope_end(&ctx,&ctx.heap,&scope);
    assert(slow_pin==0 && slow_end==1 && !scope.active && !scope.journal && !ctx.heap.rc->dead.head);
    assert(ctx.heap.objects_live+2==live);
    finish(&ctx);
    puts("PASS retirement O0/H1 native-final-release handles full-width union");
}
static void old_artifact_case(void) {
    MylQbeContext ctx;
    start(&ctx);
    const myl_rc_module old={.abi=4};
    const size_t bytes=ctx.heap.bytes,modules=ctx.heap.rc->metadata.modules.count;
    assert(!myl_qbe_rc_register(&ctx,&old));
    assert(ctx.trap && !strcmp(ctx.trap,"R_INTERNAL"));
    assert(ctx.heap.bytes==bytes && ctx.heap.rc->metadata.modules.count==modules);
    finish(&ctx);
    puts("PASS old ABI4 module rejected before metadata mutation");
}
int main(void) {
    success_case("cross-u32-hold",(UINT64_C(1)<<32)+3,UINT32_MAX,0,0,0,0);
    success_case("wide-OH",(UINT64_C(1)<<32)+5,(UINT64_C(1)<<32)+7,0,0,0,0);
    success_case("high-owner-only",UINT64_C(1)<<32,0,0,0,0,0);
    success_case("hold-only-high",0,UINT64_C(1)<<32,0,0,0,0);
    success_case("near-max-hold-owner-max",UINT64_MAX,UINT64_MAX-1,0,0,0,0);
    success_case("wide-backed",(UINT64_C(1)<<32)+3,(UINT64_C(1)<<32)+7,(UINT64_C(1)<<32)+9,(UINT64_C(1)<<32)+11,1,0);
    success_case("near-max-backed",UINT64_MAX,UINT64_MAX-1,UINT64_MAX,UINT64_MAX-1,1,1);
    refusal_case("payload-full",0,0);
    refusal_case("backing-full",1,0);
    refusal_case("backing-full-previous-pin",1,1);
    retiring_case();
    old_artifact_case();
    puts("ABI5 executable scope review: 12 passed, 0 failed");
    return 0;
}
