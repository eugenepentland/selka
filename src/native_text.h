#ifndef MYLANG_NATIVE_TEXT_H
#define MYLANG_NATIVE_TEXT_H
#include "native_collections.h"
/* One immutable `str` value: a four-word header followed, in the same managed
 * block, by the value's UTF-8 payload. `length` counts Unicode scalars and stays
 * at offset 0 because generated code loads that word directly as `len(text)`;
 * `bytes` counts the payload's octets, so every boundary that already holds
 * UTF-8 copies octets instead of decoding and re-encoding scalars. Bit 0 of
 * `flags` records that every scalar is below 0x80, which makes a scalar offset a
 * byte offset and every text operation a bulk byte operation. The payload holds
 * no pointer, so the collector treats a text as a leaf and never walks it. */
typedef struct myl_native_text {
    size_t length;
    size_t bytes;
    uint32_t flags;
    uint32_t reserved;
} myl_native_text;
/* `flags` bit 0: every scalar of the payload is below 0x80. */
#define MYL_TEXT_ASCII 1u
/* Byte offset of `bytes` inside one text header, which the number grammar reads
 * without a second call. */
#define MYL_TEXT_BYTES_OFFSET ((size_t)sizeof(size_t))
/* The element descriptor a text object carries in its managed header. A text is
 * a leaf whose payload holds no traced pointer, so this descriptor only names
 * the object for the allocator and the budget. */
extern const myl_native_type myl_native_text_leaf;
/* The UTF-8 payload of a text, which is co-allocated directly behind its header;
 * never NULL, and never dereferenced past `bytes`. */
static inline const unsigned char *myl_native_text_storage(const myl_native_text *text) {
    return (const unsigned char *)(text + 1);
}
/* The same payload address as a real callee, which generated code and a boundary
 * that reads the octets in place call by name. It allocates nothing. */
const unsigned char *myl_native_text_payload(const myl_native_text *);
/* A text of `bytes` payload octets for a constructor to write before it
 * publishes the scalar count with `myl_native_text_publish`. The payload is
 * zeroed, and the value is not a valid text until it is published, so it must
 * not reach generated code in between. NULL once the budget is exhausted. */
myl_native_text *myl_native_text_build(myl_native_heap *, size_t bytes);
/* Publish a built text as `scalars` Unicode scalar values whose payload was
 * written, with `plain` set when every one of them is below 0x80. */
void myl_native_text_publish(myl_native_text *, size_t scalars, int plain);
/* Byte offset of scalar `index`, which is `index` itself for ASCII text. */
size_t myl_native_text_offset(const myl_native_text *, size_t index);
/* Scalar index of byte offset `at`, the inverse of myl_native_text_offset. */
size_t myl_native_text_index(const myl_native_text *, size_t at);
/* The Unicode scalar value at scalar `index`, which must be in range. */
uint32_t myl_native_text_point_at(const myl_native_text *, size_t index);
/* Fresh text holding the octets of `input` in `[from, to)`, both of which must
 * begin a scalar. The scalar count is measured, never carried. */
myl_native_text *myl_native_text_substring(myl_native_heap *, myl_native_text *, size_t from, size_t to);
/* Octet offset of the first occurrence of a nonempty `needle`, or SIZE_MAX. Both
 * payloads are valid UTF-8, so an octet match begins a scalar in both. */
size_t myl_native_text_find_bytes(const myl_native_text *, const myl_native_text *needle);
/* Fresh text holding the scalar values of a temporary list a constructor filled,
 * which is rooted across the allocation: a text's payload is UTF-8, so the
 * construction cannot write scalars in place. NULL for a value that is not a
 * Unicode scalar value or a refused allocation. */
myl_native_text *myl_native_text_from_points(myl_native_heap *, const myl_native_list *points);
/* Fresh text holding exactly `bytes` octets copied from `input`, which must be
 * valid UTF-8: its scalar count is measured here and its ASCII flag derived.
 * NULL once the budget is exhausted or the size cannot be represented. */
myl_native_text *myl_native_text_from_utf8(myl_native_heap *, const unsigned char *, size_t);
/* One validating pass: builds the same text as from_utf8, but distinguishes a
 * malformed input (*invalid 1) from a refused allocation (*invalid 0). Both
 * failures return NULL, so from_utf8 stays a thin caller that ignores `invalid`. */
myl_native_text *myl_native_text_from_utf8_checked(myl_native_heap *, const unsigned char *, size_t, int *invalid);
/* Fresh text holding the `count` Unicode scalar values at `points`, encoded to
 * UTF-8. Every scalar must be a Unicode scalar value — at most 0x10FFFF and
 * outside the surrogate range — else nothing is built and NULL is answered. */
myl_native_text *myl_native_text_from_scalars(myl_native_heap *, const uint32_t *, size_t count);
/* Fresh text holding scalar range `[start, start+count)`, with `input` rooted
 * across the allocation. A range past the receiver is clamped by its callers. */
myl_native_text *myl_native_text_copy(myl_native_heap *, myl_native_text *, size_t start, size_t count);
myl_native_text *myl_native_text_concat(myl_native_heap *, myl_native_text *, myl_native_text *);
myl_native_text *myl_native_text_at(myl_native_heap *, myl_native_text *, int64_t);
myl_native_text *myl_native_text_slice(myl_native_heap *, myl_native_text *, int64_t, int64_t);
myl_native_list *myl_native_text_split(myl_native_heap *, myl_native_text *, myl_native_text *);
myl_native_text *myl_native_text_join(myl_native_heap *, myl_native_text *, myl_native_list *);
int myl_native_text_contains(const myl_native_text *, const myl_native_text *);
int myl_native_text_equal(const myl_native_text *, const myl_native_text *);
/* Three-way comparison in Unicode scalar order, which for two valid UTF-8
 * payloads is their byte order. This reads the payloads directly. */
int myl_native_text_compare(const myl_native_text *, const myl_native_text *);
/* Returns required byte count. Writes only if output capacity suffices. */
size_t myl_native_text_utf8(const myl_native_text *, unsigned char *, size_t);
/* Nonzero when the bytes decode as UTF-8 without a replacement or surrogate. */
int myl_native_text_valid_utf8(const unsigned char *, size_t);
#endif
