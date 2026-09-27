#ifndef MYLANG_NATIVE_RC_ALLOC_H
#define MYLANG_NATIVE_RC_ALLOC_H
#include "native_rc.h"
/* Install the production allocator on an initialized, empty native heap. */
myl_rc_status myl_rc_storage_init(myl_native_heap *);
/* Native allocation adapter: admit runtime metadata and preserve custom hooks;
 * production heaps cache the validated small single-object allocation class. */
void *myl_rc_storage_alloc(myl_native_heap *, const myl_native_type *, size_t count, unsigned region);
/* A raw backing has a stable byte descriptor, never a container's metadata. */
void *myl_rc_storage_bytes(myl_native_heap *, size_t bytes, unsigned region);
/* Raw bytes whose heap payload is left unwritten (arena payloads stay zero):
 * the caller writes every octet it will read, as for a GC block. */
void *myl_rc_storage_block(myl_native_heap *, size_t bytes, unsigned region);
/* Grow exclusively owned, unheld backing. Refusal preserves the old block. */
void *myl_rc_storage_extend(myl_native_heap *, void *, size_t count);
/* Reserved storage, including allocator metadata; excludes RC core metadata. */
size_t myl_rc_storage_reserved(const myl_native_heap *);
/* Heap-wide teardown support for the production allocator. */
typedef void (*myl_rc_extent_visitor)(myl_native_heap *, void *payload, void *context);
/* Visit every allocated heap payload that has not been retired (live, or
 * queued for death: DYING in its mark), each exactly once and in no fixed
 * order. Arena payloads are not heap extents. The visitor must not allocate,
 * retire or release; it may read and write the payload. */
void myl_rc_storage_visit(myl_native_heap *, myl_rc_extent_visitor, void *context);
/* Free every heap extent at once without walking edges or running
 * finalizers, discharge their budget, drop the dead queue and subtract them
 * from objects_live. The caller has abandoned every reference into heap
 * storage (frames, scopes, pins); registered metadata survives and the heap
 * accepts new allocations afterwards. No drain may be active. */
void myl_rc_storage_release_all(myl_native_heap *);
#endif
