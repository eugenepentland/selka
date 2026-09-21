#ifndef MYLANG_NATIVE_COLLECTIONS_H
#define MYLANG_NATIVE_COLLECTIONS_H
#include "native_heap.h"
typedef struct {
    size_t length, capacity;
    uint64_t generation;
    const myl_native_type *element;
    void *storage;
    myl_native_region *region; /* NULL for managed lists and heap-owned buffers */
    myl_native_drop_link work;
} myl_native_list;
/* List identity is stable across backing growth. All element storage is native
 * typed bytes; managed fields are traced by the element descriptor. */
myl_native_list *myl_native_list_new(myl_native_heap *, const myl_native_type *, size_t capacity);
int myl_native_list_append(myl_native_heap *, myl_native_list *, const void *value);
/* Grow path for one scalar element already in a register: the low
 * `element->size` bytes of `value` in little-endian order are the element.
 * Emitted code answers the capacity-sufficient case inline and calls this only
 * when the backing must grow, so this never has to be cheap. */
int myl_native_list_append_scalar(myl_native_heap *, myl_native_list *, uint64_t value);
int myl_native_list_get(const myl_native_list *, size_t index, void *output);
int myl_native_list_set(myl_native_list *, size_t index, const void *value);
int myl_native_list_pop(myl_native_list *, void *output);
int myl_native_list_pop_at(myl_native_list *, int64_t index, void *output);
int myl_native_list_clear(myl_native_list *);
/* Python-shaped list methods. `extend`/`insert` may allocate and return zero on
 * refusal; `remove`/`index` answer 1 found, 0 absent and negative on comparison
 * failure. `sort` stably orders signed integers, unsigned integers, binary64
 * values (with NaNs last), or text pointers in Unicode scalar order. */
int myl_native_list_extend(myl_native_heap *, myl_native_list *, const myl_native_list *other);
int myl_native_list_insert(myl_native_heap *, myl_native_list *, int64_t index, const void *value);
int myl_native_list_remove(myl_native_list *, const void *value);
int myl_native_list_index(const myl_native_list *, const void *value, int64_t *output);
void myl_native_list_reverse(myl_native_list *);
int myl_native_list_sort(myl_native_list *, unsigned order);
myl_native_list *myl_native_list_copy(myl_native_heap *, const myl_native_list *input);
/* `values[start:stop:step]` endpoints. An omitted endpoint arrives as one of
 * these sentinels, which no source expression can spell. */
#define MYL_NATIVE_SLICE_FIRST INT64_MIN
#define MYL_NATIVE_SLICE_LAST INT64_MAX
/* Fresh stepped slice under Python's endpoint rules. A zero step or a refused
 * allocation returns NULL. */
myl_native_list *myl_native_list_slice_step(myl_native_heap *, myl_native_list *, int64_t start, int64_t stop, int64_t step);
#endif
