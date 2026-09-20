#define _POSIX_C_SOURCE 200809L
#include "qbe_runtime.h"
#ifdef MYL_MAXPERF_STATS_ARENA
#include "arena_heap.h"
#endif

#include <assert.h>
#include <stdlib.h>

uint64_t __wrap_myl_qbe_on_stack(uint64_t (*entry)(void *), MylQbeContext *ctx);
void myl_maxperf_capture_heap_stats(MylQbeContext *ctx);

static uint64_t guest(void *context) { return context ? 73 : 0; }

uint64_t __real_myl_qbe_on_stack(uint64_t (*entry)(void *), MylQbeContext *ctx) {
#ifdef MYL_MAXPERF_STATS_ARENA
    myl_native_heap_init(&ctx->heap, SIZE_MAX);
    assert(myl_native_heap_alloc_block(&ctx->heap, 32, 32));
#else
    ctx->heap.allocations = 11;
    ctx->heap.collections = 3;
    ctx->heap.bytes = 4096;
#endif
    return entry(ctx);
}

int main(void) {
    MylQbeContext context = {0};
    assert(setenv("MYLANG_MAXPERF_HEAP_STATS", "1", 1) == 0);
    assert(__real_myl_qbe_on_stack(guest, &context) == 73);
    myl_maxperf_capture_heap_stats(&context);
#ifdef MYL_MAXPERF_STATS_ARENA
    myl_native_heap_destroy(&context.heap);
#endif
    return 0;
}
