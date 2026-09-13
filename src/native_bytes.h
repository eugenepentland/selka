#ifndef MYLANG_NATIVE_BYTES_H
#define MYLANG_NATIVE_BYTES_H
#include "native_text.h"
/* Immutable managed byte strings share the managed list representation with a
 * one-byte stride, so equality, tracing and indexing reuse the list runtime. */
typedef myl_native_list myl_native_bytes;
/* Status of a fallible byte conversion; only OK publishes a value. */
enum { MYL_BYTES_OK = 0, MYL_BYTES_MEMORY = 1, MYL_BYTES_RANGE = 2, MYL_BYTES_INVALID = 3 };
myl_native_bytes *myl_native_bytes_new(myl_native_heap *, const unsigned char *, size_t);
myl_native_bytes *myl_native_bytes_concat(myl_native_heap *, myl_native_bytes *, myl_native_bytes *);
/* Clamped Python endpoints; a reversed interval produces an empty byte string. */
myl_native_bytes *myl_native_bytes_slice(myl_native_heap *, myl_native_bytes *, int64_t, int64_t);
/* First index of a contiguous subsequence, or -1 when it is absent. */
int64_t myl_native_bytes_find(const myl_native_bytes *, const myl_native_bytes *);
int myl_native_bytes_starts_with(const myl_native_bytes *, const myl_native_bytes *);
int myl_native_bytes_ends_with(const myl_native_bytes *, const myl_native_bytes *);
/* Membership of one octet; values outside 0..255 are never present. */
int myl_native_bytes_has_byte(const myl_native_bytes *, int64_t);
/* Split by a nonempty separator, keeping leading and trailing empty pieces. */
myl_native_list *myl_native_bytes_split(myl_native_heap *, myl_native_bytes *, myl_native_bytes *);
myl_native_bytes *myl_native_bytes_join(myl_native_heap *, myl_native_bytes *, myl_native_list *);
myl_native_list *myl_native_bytes_to_list(myl_native_heap *, myl_native_bytes *);
/* Reports MYL_BYTES_RANGE for an element outside 0..255 without allocating. */
myl_native_bytes *myl_native_bytes_from_list(myl_native_heap *, myl_native_list *, int *status);
myl_native_text *myl_native_bytes_hex(myl_native_heap *, myl_native_bytes *);
/* Reports MYL_BYTES_INVALID for odd lengths and non-hexadecimal digits. */
myl_native_bytes *myl_native_bytes_from_hex(myl_native_heap *, myl_native_text *, int *status);
myl_native_bytes *myl_native_bytes_encode(myl_native_heap *, myl_native_text *);
/* Reports MYL_BYTES_INVALID for byte sequences that are not valid UTF-8. */
myl_native_text *myl_native_bytes_decode(myl_native_heap *, myl_native_bytes *, int *status);
#endif
