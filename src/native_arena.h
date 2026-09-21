#ifndef MYLANG_NATIVE_ARENA_H
#define MYLANG_NATIVE_ARENA_H
#include "native_heap.h"
/* Internal bulk allocator. Payloads grow upwards and compact side descriptors
 * grow downwards in the same allocation. No GC header precedes a payload. */
void *myl_native_arena_alloc(myl_native_heap *, const myl_native_type *, size_t, unsigned);
unsigned myl_native_arena_region(const myl_native_heap *, const void *);
const myl_native_type *myl_native_arena_element(const myl_native_heap *, const void *);
/* Scan live region contents for references into the tracing heap. Arena-to-arena
 * edges need no traversal because every allocation survives until scope exit. */
void myl_native_arena_trace(myl_native_heap *, void (*)(myl_native_heap *, const myl_native_type *, const void *));
void myl_native_arena_release(myl_native_heap *, unsigned);
#endif
