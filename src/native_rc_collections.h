#ifndef MYLANG_NATIVE_RC_COLLECTIONS_H
#define MYLANG_NATIVE_RC_COLLECTIONS_H
#include "native_collections.h"
#include "native_rc_values.h"
/* All mutators borrow their receiver and inputs. Successful destructive reads
 * initialize one owned output; ordinary native get/index reads stay borrowed. */
/* Nonmutating, nonallocating admission for one immediate scalar room append.
 * False preserves the original registration/drain/publication path. */
int myl_rc_list_plain_ready(myl_native_heap *, const myl_native_list *);
/* Identical admission with an LTO inline hint for certified nested loops. */
int myl_rc_list_plain_ready_hot(myl_native_heap *, const myl_native_list *);
/* Static list images can need their first clone before any list allocation. */
myl_rc_status myl_rc_list_require(myl_native_heap *);
int myl_rc_list_append(myl_native_heap *, myl_native_list *, const void *);
int myl_rc_list_insert(myl_native_heap *, myl_native_list *, int64_t, const void *);
int myl_rc_list_set(myl_native_heap *, myl_native_list *, size_t, const void *);
int myl_rc_list_pop(myl_native_heap *, myl_native_list *, void *);
int myl_rc_list_pop_at(myl_native_heap *, myl_native_list *, int64_t, void *);
int myl_rc_list_clear(myl_native_heap *, myl_native_list *);
int myl_rc_list_remove(myl_native_heap *, myl_native_list *, const void *);
/* Dictionary-private bookkeeping owns backing only; its embedded element
 * descriptor is never consulted when the bookkeeping header is destroyed. */
myl_native_list *myl_rc_list_storage_new(myl_native_heap *, const myl_native_type *, size_t, unsigned);
int myl_rc_list_storage_reserve(myl_native_heap *, myl_native_list *, size_t);
/* Abort a pointer list produced by splitting one borrowed input. Arena parts
 * other than that input are fresh products and must undo their own edges. */
void myl_rc_list_abort_parts(myl_native_heap *, myl_native_list *, const void *borrowed);
typedef struct {
    myl_native_list *values, *source, *keys;
    uint64_t shape, offsets, reverse;
} myl_rc_sort_request;
int myl_rc_list_sort_keyed(myl_native_heap *, const myl_rc_sort_request *);
#endif
