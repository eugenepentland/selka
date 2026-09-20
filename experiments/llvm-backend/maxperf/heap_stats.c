#define _POSIX_C_SOURCE 200809L
#include "qbe_runtime.h"

#ifdef MYL_MAXPERF_STATS_ARENA
#include "arena_heap.h"
#endif

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>

uint64_t __real_myl_qbe_on_stack(uint64_t (*entry)(void *), MylQbeContext *ctx);

static int enabled(void) {
    const char *value = getenv("MYLANG_MAXPERF_HEAP_STATS");
    return value && *value && !(value[0] == '0' && value[1] == '\0');
}

/* Stable diagnostic hook: call after guest execution and before heap destroy.
 * It is inert unless MYLANG_MAXPERF_HEAP_STATS is enabled. */
void myl_maxperf_capture_heap_stats(MylQbeContext *ctx) {
    if (!ctx || !enabled()) return;
    size_t allocations = ctx->heap.allocations;
    size_t collections = ctx->heap.collections;
    size_t live_bytes = ctx->heap.bytes;
    size_t reserved_bytes = 0, chunks = 0;
    const char *kind = "gc";
#ifdef MYL_MAXPERF_STATS_ARENA
    myl_maxperf_arena_report report;
    if (myl_maxperf_arena_get_report(&ctx->heap, &report)) {
        allocations = report.allocations;
        collections = report.collections;
        live_bytes = report.live_bytes;
        reserved_bytes = report.reserved_bytes;
        chunks = report.chunks;
    }
    kind = "arena";
#endif
    struct rusage usage;
    long peak_rss_kib = getrusage(RUSAGE_SELF, &usage) ? -1 : usage.ru_maxrss;
    fprintf(stderr,
            "{\"mylang_maxperf_heap\":{\"kind\":\"%s\","
            "\"allocations\":%zu,\"collections\":%zu,"
            "\"live_bytes\":%zu,\"reserved_bytes\":%zu,"
            "\"chunks\":%zu,\"peak_rss_kib\":%ld}}\n",
            kind, allocations, collections, live_bytes, reserved_bytes,
            chunks, peak_rss_kib);
}

uint64_t __wrap_myl_qbe_on_stack(uint64_t (*entry)(void *), MylQbeContext *ctx) {
    uint64_t result = __real_myl_qbe_on_stack(entry, ctx);
    myl_maxperf_capture_heap_stats(ctx);
    return result;
}
