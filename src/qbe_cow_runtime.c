/* D9 phase 2 transfer hook: the same output/root contract as stage 3a's
 * eager myl_qbe_value_copy, with shallow sharing over the tracing collector.
 * COW-SHARED-1 and COW-NESTED-1. */
#include "native_cow.h"
#include "qbe_runtime.h"
#include <string.h>

int myl_qbe_cow_transfer(void *context, const myl_native_type *type,
                         const void *value, void *output, uint32_t children) {
    myl_native_heap *heap = myl_qbe_heap(context);
    if (output != value) memmove(output, value, type->size);
    myl_native_root root;
    myl_native_root_push(heap, &root, output, type);
    int done = children == 2 ? myl_native_cow_copy_source_children(heap, type, output)
                           : children ? myl_native_cow_share_children(heap, type, output)
                                      : myl_native_cow_share_value(heap, type, output);
    myl_native_root_pop(heap, &root);
    if (!done) myl_qbe_fail_allocation(context);
    return done;
}

int myl_qbe_cow_unbox(void *context, const myl_native_type *type,
                      void *box, void *output) {
    int done = myl_native_cow_unbox(myl_qbe_heap(context), type, box, output);
    if (!done) myl_qbe_fail_allocation(context);
    return done;
}
