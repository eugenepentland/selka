#ifndef MYLANG_NATIVE_TEXT_H
#define MYLANG_NATIVE_TEXT_H
#include "native_collections.h"
typedef myl_native_list myl_native_text;
myl_native_text *myl_native_text_from_utf8(myl_native_heap *, const unsigned char *, size_t);
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
