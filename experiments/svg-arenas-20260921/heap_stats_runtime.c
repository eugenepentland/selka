#include "qbe_runtime.h"
#include <stdio.h>
static size_t peak_charged_bytes;
void myl_stats_observe(myl_native_heap *heap) {
    if (heap->bytes > peak_charged_bytes) peak_charged_bytes = heap->bytes;
}
void myl_stats_report(myl_native_heap *h) {
    myl_stats_observe(h);
    fprintf(stderr, "MYLANG_HEAP_STATS {\"total_allocations\":%zu,\"gc_allocations\":%zu,\"collections\":%zu,\"charged_bytes_final\":%zu,\"peak_charged_bytes\":%zu,\"objects_live\":%zu,\"arena_scopes\":%llu,\"arena_released\":%llu,\"arena_allocations\":%llu,\"arena_chunks\":%llu,\"arena_chunks_live\":%zu,\"arena_reserved_bytes\":%zu,\"arena_peak_reserved_bytes\":%zu}\n",
      h->allocations, h->allocations - (size_t)h->arena.allocations, h->collections, h->bytes,
      peak_charged_bytes, h->objects_live, (unsigned long long)h->arena.scopes,
      (unsigned long long)h->arena.released, (unsigned long long)h->arena.allocations,
      (unsigned long long)h->arena.chunks, h->arena.chunks_live,
      h->arena.reserved_bytes, h->arena.peak_reserved_bytes);
}
