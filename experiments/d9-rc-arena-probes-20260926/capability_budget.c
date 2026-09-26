#include "qbe_runtime.h"
#include "native_providers.h"
#include "native_collections.h"
#include "native_rc_stats.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
myl_native_heap *myl_qbe_heap(void *context) { return &((MylQbeContext *)context)->heap; }
uint64_t myl_qbe_failed(void *context) { return ((MylQbeContext *)context)->trap != NULL; }
void myl_qbe_fail(void *context, const char *code) {
    MylQbeContext *ctx = context;
    if (!ctx->trap) ctx->trap = code;
}
void myl_qbe_fail_allocation(void *context) { myl_qbe_fail(context, "AllocationRefused"); }
void myl_qbe_fail_capability(void *context) { myl_qbe_fail(context, "InvalidCapability"); }
int main(void) {
    char names[124] = "A,";
    memset(names + 2, 'Z', sizeof names - 3);
    names[sizeof names - 1] = 0;
    MylangNativeProviders providers = {.environment_context = names};
    unsigned refused = 0, partial = 0, success = 0;
    for (size_t extra = 0; extra <= 512 * 1024; extra += 16 * 1024) {
        MylQbeContext ctx = {0};
        ctx.providers = &providers;
        myl_native_heap_init(&ctx.heap, 1024 * 1024);
        assert(ctx.heap.rc);
        ctx.heap.limit = ctx.heap.bytes + extra;
        myl_native_list *list = myl_qbe_environment_names(&ctx, MYL_QBE_ENVIRONMENT_ROOT);
        if (list) { assert(list->length == 2 && !ctx.trap); ++success; myl_rc_owner_release(&ctx.heap, list); }
        else { assert(ctx.trap); ++refused; }
        myl_rc_counters counts;
        assert(myl_rc_stats_snapshot(&ctx.heap, &counts));
        if (!list && counts.events[MYL_RC_STAT_HEAP_ALLOCATE] >= 3) ++partial;
        assert(counts.events[MYL_RC_STAT_HEAP_ALLOCATE] == counts.events[MYL_RC_STAT_RETIRE]);
        assert(!ctx.heap.roots && !ctx.heap.objects_live);
        myl_native_heap_destroy(&ctx.heap);
        assert(!ctx.heap.bytes);
    }
    assert(refused && partial && success);
    printf("capability budget rollback: %u refused, %u after partial construction, %u succeeded\n", refused, partial, success);
    return 0;
}
