#ifndef MYLANG_NATIVE_OWNED_H
#define MYLANG_NATIVE_OWNED_H
#include "native_collections.h"
/* Owned buffers retain a stable typed header; operations consume moved inputs.
 * Return 0 success, 1 Capacity, 2 NoCapacity, 3 Bounds, -1 host allocation failure. */
typedef myl_native_list myl_native_owned_buffer;
int myl_native_owned_new(myl_native_heap *, const myl_native_type *, int64_t capacity, size_t capacity_limit, myl_native_owned_buffer **);
int myl_native_owned_append(myl_native_heap *, myl_native_owned_buffer *, void *value);
int myl_native_owned_set(myl_native_heap *, myl_native_owned_buffer *, int64_t index, void *value);
int myl_native_owned_take(myl_native_owned_buffer *, int64_t index, void *output);
int myl_native_owned_truncate(myl_native_heap *, myl_native_owned_buffer *, int64_t length);
int myl_native_owned_resize(myl_native_heap *, myl_native_owned_buffer *, int64_t length, void *fill);
int myl_native_owned_reserve(myl_native_heap *, myl_native_owned_buffer *, int64_t capacity, size_t capacity_limit);
void myl_native_owned_drop(myl_native_heap *, const myl_native_type *, void *value);
#endif
