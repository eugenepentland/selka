/* Arena scopes for the native backend: the execution context owns the region
   depth, so a trap, a `?` propagation, a loop exit or a plain return all close
   exactly the scopes the frame opened. */
#include "qbe_arena.h"
void myl_qbe_fail_arena_escape(void *context) { myl_qbe_fail(context, "R_ARENA_ESCAPE"); }
int myl_qbe_region_begin(void *context) {
    if (myl_native_region_begin(myl_qbe_heap(context))) return 1;
    myl_qbe_fail_allocation(context);
    return 0;
}
void myl_qbe_region_end(void *context) { myl_native_region_end(myl_qbe_heap(context)); }
uint64_t myl_qbe_region_mark(void *context) { return myl_qbe_heap(context)->region_depth; }
void myl_qbe_region_restore(void *context, uint64_t mark) {
    myl_native_heap *heap = myl_qbe_heap(context);
    while (heap->region_depth > mark) myl_native_region_end(heap);
}
int myl_qbe_region_retains(void *context, const myl_native_type *type, const void *value) {
    return myl_native_region_retains(myl_qbe_heap(context), type, value);
}
int myl_qbe_region_check(void *context, const void *container, const myl_native_type *type, const void *value) {
    return myl_native_region_check(myl_qbe_heap(context), container, type, value);
}
int myl_qbe_region_escape(void *context, const myl_native_type *type, const void *value, void *output) {
    if (myl_native_region_escape(myl_qbe_heap(context), type, value, output)) return 1;
    myl_qbe_fail_allocation(context);
    return 0;
}
