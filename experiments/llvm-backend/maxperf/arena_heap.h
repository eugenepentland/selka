#ifndef MYLANG_MAXPERF_ARENA_HEAP_H
#define MYLANG_MAXPERF_ARENA_HEAP_H

#include "native_heap.h"

/* Diagnostic counters are read only when a harness explicitly asks for them;
 * the arena writes no timed-path output. */
typedef struct {
    size_t allocations;
    size_t live_bytes;
    size_t reserved_bytes;
    size_t chunks;
    size_t collections;
} myl_maxperf_arena_report;

/* Return zero when `heap` is not a live max-performance arena. */
int myl_maxperf_arena_get_report(const myl_native_heap *heap,
                                 myl_maxperf_arena_report *report);

#endif
