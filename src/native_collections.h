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
int myl_native_list_get(const myl_native_list *, size_t index, void *output);
int myl_native_list_set(myl_native_list *, size_t index, const void *value);
int myl_native_list_pop(myl_native_list *, void *output);
int myl_native_list_clear(myl_native_list *);
#endif
