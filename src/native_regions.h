#ifndef MYLANG_NATIVE_REGIONS_H
#define MYLANG_NATIVE_REGIONS_H
#include "native_dictionary.h"
/* Deepest arena depth reachable from one native value's bytes. Managed
 * references are not followed past the first hop: the store barrier keeps an
 * object from ever referencing a younger arena, so one hop is already exact. */
unsigned myl_native_region_reach(const myl_native_type *type, const void *value);
/* Nonzero when storing this value into that container respects the arena
 * ordering; zero is the located R_ARENA_ESCAPE case. */
int myl_native_region_check(myl_native_heap *heap, const void *container,
                            const myl_native_type *type, const void *value);
/* Nonzero when a value still reaches the innermost arena about to be released. */
int myl_native_region_retains(myl_native_heap *heap, const myl_native_type *type, const void *value);
/* Deep-copy the innermost arena's part of the graph reachable from value into
 * the enclosing region, sharing objects that already live there and preserving
 * sharing and cycles inside the copy. Zero on allocation failure. */
int myl_native_region_escape(myl_native_heap *heap, const myl_native_type *type,
                             const void *value, void *output);
#endif
