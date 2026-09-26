#ifndef MYLANG_NATIVE_RC_ALLOC_H
#define MYLANG_NATIVE_RC_ALLOC_H
#include "native_rc.h"
/* Install the production allocator on an initialized, empty native heap. */
myl_rc_status myl_rc_storage_init(myl_native_heap *);
/* A raw backing has a stable byte descriptor, never a container's metadata. */
void *myl_rc_storage_bytes(myl_native_heap *, size_t bytes, unsigned region);
/* Grow exclusively owned, unheld backing. Refusal preserves the old block. */
void *myl_rc_storage_extend(myl_native_heap *, void *, size_t count);
/* Reserved storage, including allocator metadata; excludes RC core metadata. */
size_t myl_rc_storage_reserved(const myl_native_heap *);
#endif
