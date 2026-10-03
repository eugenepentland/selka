#ifndef MYLANG_NATIVE_BYTES_H
#define MYLANG_NATIVE_BYTES_H
#include "native_text.h"
/* Immutable managed byte strings share the managed list representation with a
 * one-byte stride, so equality, tracing and indexing reuse the list runtime. */
typedef myl_native_list myl_native_bytes;
/* Status of a fallible byte conversion; only OK publishes a value. */
enum { MYL_BYTES_OK = 0, MYL_BYTES_MEMORY = 1, MYL_BYTES_RANGE = 2, MYL_BYTES_INVALID = 3 };
myl_native_bytes *myl_native_bytes_new(myl_native_heap *, const unsigned char *, size_t);
/* A fresh byte string holding the input's current octets. The copy shares
 * nothing with the input, so a later append through an alias of a mutable
 * buffer cannot change it. */
myl_native_bytes *myl_native_bytes_copy(myl_native_heap *, myl_native_bytes *);
myl_native_bytes *myl_native_bytes_concat(myl_native_heap *, myl_native_bytes *, myl_native_bytes *);
/* A byte string that reads the clamped range `source[start:end]` without copying
 * it. The view's own header retains the source's backing block, so the octets
 * outlive the byte string that first owned them, and every read operation —
 * length, indexing, iteration, comparison, search, slicing, decode, numeric
 * parsing — reads a view exactly as it reads a byte string. */
myl_native_bytes *myl_native_bytes_view(myl_native_heap *, myl_native_bytes *source, int64_t start, int64_t end);
/* Unicode scalars in a byte string, validated in the same nonallocating pass, so
 * measuring a range never decodes it. Reports MYL_BYTES_INVALID, and no count,
 * for exactly the sequences the decoder rejects. The range form is the same
 * scanner over raw octets, which is what a view of a larger buffer passes. */
int64_t myl_native_bytes_scalar_count(const myl_native_bytes *, int *status);
int64_t myl_native_bytes_scalar_count_range(const myl_native_bytes *, int64_t, int64_t, int *status);
/* Borrow one clamped range and publish its length without allocating. */
const unsigned char *myl_native_bytes_range(const myl_native_bytes *, int64_t, int64_t, size_t *length);
/* Clamped Python endpoints; a reversed interval produces an empty byte string. */
myl_native_bytes *myl_native_bytes_slice(myl_native_heap *, myl_native_bytes *, int64_t, int64_t);
/* First index of a contiguous subsequence, or -1 when it is absent. */
int64_t myl_native_bytes_find(const myl_native_bytes *, const myl_native_bytes *);
/* First index at or after `start` holding any octet of the set `values`, or -1.
 * An empty set finds nothing, a negative start clamps to zero, and a start at or
 * past the end finds nothing, so a search never traps where a read would. */
int64_t myl_native_bytes_find_any(const myl_native_bytes *, const myl_native_bytes *values, int64_t start);
int myl_native_bytes_starts_with(const myl_native_bytes *, const myl_native_bytes *);
/* Lexicographic octet order of two byte strings: -1, 0 or 1. */
int myl_native_bytes_compare(const myl_native_bytes *, const myl_native_bytes *);
/* Payload equality without allocation or structural scratch; views read their
 * retained storage exactly as owned byte strings do. Null equals only null. */
int myl_native_bytes_equal(const myl_native_bytes *, const myl_native_bytes *);
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
/* Decode one clamped range directly, so `s[a:b].decode()` never builds the
 * intermediate byte string. Same status contract as `myl_native_bytes_decode`. */
myl_native_text *myl_native_bytes_decode_range(myl_native_heap *, myl_native_bytes *, int64_t, int64_t, int *status);
/* In-place octet-buffer operations. A buffer is an ordinary managed byte string
 * whose header keeps spare capacity: `length` counts the octets it holds and
 * `capacity` the octets its backing can hold, so an append writes into that
 * spare capacity and growth doubles it instead of allocating per fragment. The
 * buffer's identity is stable across growth, which is what lets one managed
 * object be mutated through the ordinary byte-string surface. A frozen
 * `bytes` literal is shared by the whole image, so every mutating entry point
 * refuses an immortal receiver rather than writing storage the image owns. */
/* One write, one rejected argument or frozen receiver, one refused allocation. */
enum { MYL_BYTES_FAILED = 0, MYL_BYTES_WROTE = 1, MYL_BYTES_REFUSED = 2 };
/* The buffer's current octets as an immutable byte string that reads them where
 * they are, retaining their block: `bytes(buffer)` copies no octet. The buffer
 * keeps its octets and length but loses its spare capacity, so its next write
 * detaches them into a private block first and a published snapshot can never be
 * written through. NULL after an exhausted allocation budget. */
myl_native_bytes *myl_native_bytes_buffer_snapshot(myl_native_heap *, myl_native_bytes *buffer);
/* Grow the backing so `extra` more octets fit, keeping `length` and content. */
int myl_native_bytes_buffer_reserve(myl_native_heap *, myl_native_bytes *, int64_t extra);
/* Append one octet; a value outside 0..255 is refused without writing. */
int myl_native_bytes_buffer_append_byte(myl_native_heap *, myl_native_bytes *, int64_t value);
/* Append `data[start:end]`; a negative start, an end below start or an end past
 * `len(data)` is refused before anything is written. `data` may be the buffer. */
int myl_native_bytes_buffer_append_range(myl_native_heap *, myl_native_bytes *, myl_native_bytes *data, int64_t start, int64_t end);
/* Append the UTF-8 encoding of text, which the shared encoder writes straight
 * into the buffer's capacity. */
int myl_native_bytes_buffer_append_utf8(myl_native_heap *, myl_native_bytes *, myl_native_text *text);
/* Append the decimal spelling of an integer, formatted into the buffer's own
 * capacity with no intermediate text or byte value. */
int myl_native_bytes_buffer_append_int(myl_native_heap *, myl_native_bytes *, int64_t value);
/* Append `count` octets of raw storage the caller owns, which must not be the
 * receiver's own backing: growth may reallocate that, while this source cannot
 * move. The float formatter reaches the buffer through this entry point. */
int myl_native_bytes_buffer_append_raw(myl_native_heap *, myl_native_bytes *, const unsigned char *data, size_t count);
/* Copy `count` octets between two storage ranges the caller has already
 * validated. Emitted code reaches this only on the capacity-sufficient append
 * path, where the destination is the receiver's own spare capacity and the
 * source is a range of another byte string or of the receiver's already
 * published octets. Nothing here allocates, collects or roots, so the copy
 * neither observes nor changes collector state, and the caller reaches it
 * without the root protocol. */
void myl_native_bytes_copy_octets(void *destination, const void *source, size_t count);
#endif
