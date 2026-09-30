#include "native_rc_collections.h"

/* Separate caller TU uses the public declaration and the callable address. */
int (*volatile query_address)(myl_native_heap *, const myl_native_list *) = myl_rc_list_plain_ready;
void select_query(int hot) { query_address=hot?myl_rc_list_plain_ready_hot:myl_rc_list_plain_ready; }
int query_from_other_tu(myl_native_heap *heap, const myl_native_list *list) {
    return query_address(heap, list);
}
