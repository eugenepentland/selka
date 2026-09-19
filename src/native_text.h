#ifndef MYLANG_NATIVE_TEXT_H
#define MYLANG_NATIVE_TEXT_H
#include "native_collections.h"
typedef myl_native_list myl_native_text;
/* The one-scalar element descriptor every `str` value shares. */
extern const myl_native_type myl_native_text_point;
/* Fresh zeroed text of `count` scalars whose header and scalars share one
 * allocation: the managed block is a `myl_native_list` header followed by the
 * scalars, so a text costs one allocation instead of a list object plus a
 * separate backing array, and the collector never walks it. NULL once the
 * budget is exhausted or `count` cannot be represented. */
myl_native_text *myl_native_text_new(myl_native_heap *, size_t count);
/* Fresh text holding `count` scalars starting at `start`, with `input` rooted
 * across the allocation. NULL once the allocation budget is exhausted. */
myl_native_text *myl_native_text_copy(myl_native_heap *, myl_native_text *, size_t start, size_t count);
myl_native_text *myl_native_text_from_utf8(myl_native_heap *, const unsigned char *, size_t);
/* One validating pass: builds the same text as from_utf8, but distinguishes a
 * malformed input (*invalid 1) from a refused allocation (*invalid 0). Both
 * failures return NULL, so from_utf8 stays a thin caller that ignores `invalid`. */
myl_native_text *myl_native_text_from_utf8_checked(myl_native_heap *, const unsigned char *, size_t, int *invalid);
myl_native_text *myl_native_text_concat(myl_native_heap *, myl_native_text *, myl_native_text *);
myl_native_text *myl_native_text_at(myl_native_heap *, myl_native_text *, int64_t);
myl_native_text *myl_native_text_slice(myl_native_heap *, myl_native_text *, int64_t, int64_t);
myl_native_list *myl_native_text_split(myl_native_heap *, myl_native_text *, myl_native_text *);
myl_native_text *myl_native_text_join(myl_native_heap *, myl_native_text *, myl_native_list *);
int myl_native_text_contains(const myl_native_text *, const myl_native_text *);
int myl_native_text_equal(const myl_native_text *, const myl_native_text *);
/* Returns required byte count. Writes only if output capacity suffices. */
size_t myl_native_text_utf8(const myl_native_text *, unsigned char *, size_t);
/* Nonzero when the bytes decode as UTF-8 without a replacement or surrogate. */
int myl_native_text_valid_utf8(const unsigned char *, size_t);
#endif
