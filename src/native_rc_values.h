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
/* RC-v3 semantic publication modes. The low two bits select direct payloads,
 * children of a fresh shallow result, or source children (the source remains
 * unchanged). TAKE consumes ordinary owned input only; a physical loan always
 * uses COPY. CHILDREN and SOURCE_CHILDREN may not be combined. */
#define MYL_RC_HISTORY_DIRECT 0u
#define MYL_RC_HISTORY_CHILDREN 1u
#define MYL_RC_HISTORY_SOURCE_CHILDREN 2u
#define MYL_RC_HISTORY_TAKE 4u
/* Frame-private physical loans copy inline bytes and acquire H for every O/H
 * leaf without marks, pin snapshots or region escape. Raw unique cleanup is
 * forbidden. Failure leaves the source unchanged and destination empty. */
int myl_rc_native_loan(myl_native_heap *, const myl_native_type *, void *dst, const void *src);
/* Clear and release one loan H per managed leaf; no O edge is released. */
void myl_rc_native_unloan(myl_native_heap *, const myl_native_type *, void *value);
/* Transactional semantic SHARE plus physical COPY/TAKE into empty destination.
 * Reused mutable payloads commit SHARED; fresh pinned shells stay unmarked.
 * Refusal preserves source pointers, history and tokens, and empties output.
 * A COPY source may be an ordinary value or a frame-private physical loan. */
int myl_rc_native_publish(myl_native_heap *, const myl_native_type *, void *dst,
                          void *src, unsigned region, unsigned semantic_mode);
/* Checked raw storage for count native elements. */
void *myl_rc_native_storage(myl_native_heap *, const myl_native_type *, size_t count, unsigned region);
/* Convert a NULL native constructor result without losing its first failure. */
myl_rc_status myl_rc_native_result(myl_native_heap *, const void *);
/* Undo an unpublished constructor, including its committed arena-to-heap
 * edges. Arena bytes stay reserved but become an empty object for teardown. */
void myl_rc_native_abort(myl_native_heap *, void *);
#endif
