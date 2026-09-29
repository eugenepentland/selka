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
 * values (with NaNs last), text pointers in Unicode scalar order, or bytes
 * pointers in unsigned octet order. Dispatch codes 0..3 retain their meaning;
 * code 4 is bytes. */
int myl_native_list_extend(myl_native_heap *, myl_native_list *, const myl_native_list *other);
int myl_native_list_insert(myl_native_heap *, myl_native_list *, int64_t index, const void *value);
int myl_native_list_remove(myl_native_list *, const void *value);
int myl_native_list_index(const myl_native_list *, const void *value, int64_t *output);
void myl_native_list_reverse(myl_native_list *);
int myl_native_list_sort(myl_native_list *, unsigned order);
/* Stable sort of `source` by the key at the same position of `keys` (one
   scalar or a flat tuple of scalars, described by `shape` and `offsets` as
   native_collections.c documents), descending when `reverse` is nonzero:
   in place when `values` is `source`, else gathered into the empty list
   `values`, which has room for every element. Returns 0, with no element
   moved, when the lengths or the target do not fit or scratch memory is
   refused; the key list's contents are consumed either way. */
int myl_native_list_sort_keyed(myl_native_list *values, myl_native_list *source, myl_native_list *keys, uint64_t shape, uint64_t offsets, uint64_t reverse);
myl_native_list *myl_native_list_copy(myl_native_heap *, const myl_native_list *input);
/* Whether `payload` is a list header — a `list`, `bytes` or `byte_buffer` whose
 * storage it owns, not a byte-string view — read from its object header. */
int myl_native_list_header(const void *payload);
/* The exact descriptor identity, also used by the generated RC scope path. */
extern const myl_native_type *const myl_native_list_header_type;
/* A fresh header and private storage holding `input`'s elements, both
 * allocated at arena depth `region` (COW-UNIQUE-1). `element` describes the
 * copy's elements and becomes its storage block's descriptor: `input`'s own
 * for a list, the new dictionary's entry type for a dictionary's entry list.
 * The capacity is `input`'s own, or its length when a published snapshot
 * shares its block, so a write right after the copy does not grow it again.
 * The copy's copy-on-write flags are clear; nothing inside the elements is
 * marked. NULL on refusal. */
myl_native_list *myl_native_list_clone_at(myl_native_heap *, const myl_native_list *input, const myl_native_type *element, unsigned region);
/* `values[start:stop:step]` endpoints. An omitted endpoint arrives as one of
 * these sentinels, which no source expression can spell. */
#define MYL_NATIVE_SLICE_FIRST INT64_MIN
#define MYL_NATIVE_SLICE_LAST INT64_MAX
/* Fresh stepped slice under Python's endpoint rules. A zero step or a refused
 * allocation returns NULL. */
myl_native_list *myl_native_list_slice_step(myl_native_heap *, myl_native_list *, int64_t start, int64_t stop, int64_t step);
/* The three endpoint rules `myl_native_list_slice_step` applies, shared with
 * every other indexable receiver so a stepped slice cannot be spelled twice: an
 * omitted endpoint arrives as one of the sentinels above and is resolved here,
 * then clamped for the step's sign, and the element count rounds the distance
 * between the adjusted endpoints up to whole steps. */
int64_t myl_native_slice_start(int64_t length, int64_t start, int64_t step);
int64_t myl_native_slice_stop(int64_t length, int64_t stop, int64_t step);
uint64_t myl_native_slice_count(int64_t start, int64_t stop, int64_t step);
#endif
