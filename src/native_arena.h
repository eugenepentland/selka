#ifndef MYLANG_NATIVE_ARENA_H
#define MYLANG_NATIVE_ARENA_H
#include "native_heap.h"
/* Internal bulk allocator. Each payload follows a two-word header like a
 * tracing-heap object's, whose mark word records the arena flag, the owning
 * depth and the element count; `myl_native_header_region` reads the depth. */
void *myl_native_arena_alloc(myl_native_heap *, const myl_native_type *, size_t, unsigned);
/* Scan live region contents for references into the tracing heap. Arena-to-arena
 * edges need no traversal because every allocation survives until scope exit. */
void myl_native_arena_trace(myl_native_heap *, void (*)(myl_native_heap *, const myl_native_type *, const void *));
void myl_native_arena_release(myl_native_heap *, unsigned);
/* Fold generated code's arena window back into its chunk's `used` and close
 * it. Every runtime operation that reads or extends a chunk's used prefix calls
 * this first. A generated allocation from the window is never counted in
 * `objects_live` or the arena statistics; its bytes were charged with the
 * chunk. */
void myl_native_arena_sync(myl_native_heap *);
/* Return every retained chunk to the host. Called when the heap is destroyed
 * and when a host reservation fails, since retained chunks are the only bytes
 * the runtime can give back without losing a live allocation. */
void myl_native_arena_reclaim(myl_native_heap *);
void myl_native_arena_destroy(myl_native_heap *);
#endif
