#ifndef MYLANG_NATIVE_RC_VALUES_H
#define MYLANG_NATIVE_RC_VALUES_H
#include "native_rc_alloc.h"
/* Resolve registered ownership metadata, admitting runtime scalar/pointer
 * descriptors before construction. Complex shapes must already be registered. */
const myl_rc_shape *myl_rc_native_shape(myl_native_heap *, const myl_native_type *);
/* Typed slot operations bridge native collection ABI to pin-aware publication.
 * Copy initializes empty storage; replace/take preserve both values on refusal. */
int myl_rc_native_copy(myl_native_heap *, const myl_native_type *, void *dst, const void *src, unsigned region);
int myl_rc_native_replace(myl_native_heap *, const myl_native_type *, void *dst, const void *src, unsigned region);
int myl_rc_native_take(myl_native_heap *, const myl_native_type *, void *dst, void *src, unsigned region);
void myl_rc_native_drop(myl_native_heap *, const myl_native_type *, void *value);
/* Checked raw storage for count native elements. */
void *myl_rc_native_storage(myl_native_heap *, const myl_native_type *, size_t count, unsigned region);
/* Convert a NULL native constructor result without losing its first failure. */
myl_rc_status myl_rc_native_result(myl_native_heap *, const void *);
/* Undo an unpublished constructor, including its committed arena-to-heap
 * edges. Arena bytes stay reserved but become an empty object for teardown. */
void myl_rc_native_abort(myl_native_heap *, void *);
#endif
