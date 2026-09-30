#ifndef MYLANG_NATIVE_TEXT_H
#define MYLANG_NATIVE_TEXT_H
#include "native_collections.h"
#include <string.h>
/* One immutable `str` value. An owned text is a four-word header followed, in
 * the same managed block, by the value's UTF-8 payload; a view is the same
 * header followed by one traced pointer to the owned text whose payload it
 * reads. `length` counts Unicode scalars and stays at offset 0 because generated
 * code loads that word directly as `len(text)`; `bytes` counts the payload's
 * octets, so every boundary that already holds UTF-8 copies octets instead of
 * decoding and re-encoding scalars. Bit 0 of `flags` records that every scalar is
 * below 0x80, which makes a scalar offset a byte offset and every text operation
 * a bulk byte operation. On an owned text `hash` caches the payload's hash once a
 * dictionary has computed it, so the header stays 24 bytes and a text is never
 * rehashed; on a view the same word is the octet offset of its payload inside its
 * owner's, and a view's hash is recomputed per request. Every reader reaches the
 * octets through `myl_native_text_storage`, so no consumer can tell the two
 * apart. */
typedef struct myl_native_text {
    size_t length;
    size_t bytes;
    uint32_t flags;
    uint32_t hash;
} myl_native_text;
/* `flags` bit 0: every scalar of the payload is below 0x80. */
#define MYL_TEXT_ASCII 1u
/* `flags` bit 1: `hash` holds this text's payload hash. Never set on a view. */
#define MYL_TEXT_HASHED 2u
/* `flags` bit 2: the text is a view. It owns no octets: its payload is `bytes`
 * octets of `owner`'s payload starting at octet `hash`. */
#define MYL_TEXT_VIEW 4u
/* `flags` bit 3: the block holds a position index behind its payload
 * (TEXT-INDEX-1). Only an owned, non-ASCII text of at least MYL_TEXT_INDEX_MIN
 * octets carries one; every other text finds a scalar by walking its payload
 * from an end. */
#define MYL_TEXT_INDEXED 8u
/* `flags` bit 4: the indexed text's sample table has been filled. */
#define MYL_TEXT_SAMPLED 16u
/* `flags` bit 5: image-owned samples are ready and read-only (TEXT-INDEX-4).
 * Their cursor words stay zero; runtime lookups never modify this index. */
#define MYL_TEXT_STATIC_INDEX 32u
/* The shortest payload, in octets, that carries a position index. Below it a
 * walk from an end is at most this many octets, cheaper than the index's 16
 * bytes and its bookkeeping. */
#define MYL_TEXT_INDEX_MIN ((size_t)256)
/* Scalars between two entries of an indexed text's sample table. One four-byte
 * entry per stride keeps the table at about 3 % of the scalar count, and a
 * lookup that reaches it walks at most half a stride of scalars. */
#define MYL_TEXT_SAMPLE_STRIDE ((size_t)128)
/* The indexed payload's eight-aligned tail. Dynamic text updates its cursor
 * and lazily fills samples; static literal text carries immutable samples. */
typedef struct myl_native_text_positions {
    uint64_t scalar, octet;
    uint32_t sample[];
} myl_native_text_positions;
/* A view: a text header whose payload is a range of another text's. `owner` is
 * always an owned text (a view of a view points at the first view's owner), so
 * reading a view's octets is one hop, and the collector keeps the owner alive
 * through the element descriptor the view is allocated with, which traces this
 * one pointer. A view lives in an arena depth no shallower than its owner's, so
 * the store barrier's one-hop reach stays exact. 32 bytes: a view occupies the
 * 48-byte size class, the class a copied piece of up to 8 octets already takes. */
typedef struct myl_native_text_view {
    myl_native_text text;
    const myl_native_text *owner;
} myl_native_text_view;
/* The element descriptor every view is allocated with: one traced pointer, its
 * owner. */
extern const myl_native_type myl_native_text_view_type;
/* Bounded-piece retention policy. A piece of a text shorter than MYL_TEXT_VIEW_MIN octets is
 * copied: its copy takes no more memory than a view (both fit the 48-byte size
 * class), is contiguous and caches its hash. A longer piece is a view unless it
 * is shorter than 1/MYL_TEXT_VIEW_RATIO of its owner's octets, so a live view
 * keeps at most MYL_TEXT_VIEW_RATIO times its own octets reachable — the bound
 * that stops one short slice of a large text from retaining all of it. The
 * omitted-upper-bound tail operation shares pieces of at least nine octets
 * independently of this ratio (TEXT-VIEW-5). */
#define MYL_TEXT_VIEW_MIN ((size_t)9)
#define MYL_TEXT_VIEW_RATIO ((size_t)4)
/* Byte offset of `bytes` inside one text header, which the number grammar reads
 * without a second call. */
#define MYL_TEXT_BYTES_OFFSET ((size_t)sizeof(size_t))
/* The payload's hash, computed on first use and cached in the header. Equal
 * texts hash equally; the value is internal to one process and never persisted,
 * so the function it comes from may change. */
uint32_t myl_native_text_hash(const myl_native_text *);
/* The high and low halves of one full 64×64-bit product folded together, so
 * every output bit depends on every input bit of both factors. */
static inline uint64_t myl_native_hash_fold(uint64_t a, uint64_t b) {
    unsigned __int128 product=(unsigned __int128)a*b;
    return (uint64_t)product^(uint64_t)(product>>64);
}
/* The hash of `length` octets, which a text caches as its payload's hash: equal
 * octets hash equally whether they are a text's whole payload or a range of
 * another's, so a dictionary can probe for a slice it never builds. The payload
 * is read eight octets at a time: each word is folded into a running state by
 * one multiply, a payload of at most eight octets is read as two overlapping
 * halves and folded once, and a longer one ends on the word that finishes
 * exactly at its last octet, so no read passes the payload and every octet
 * reaches the answer. The length seeds the state, so payloads of different
 * lengths start apart. Fixed constants, no seed: the runtime has no sanctioned
 * randomness and a dictionary must behave identically on every run. Inline,
 * because the probe for a described slice hashes a few octets per lookup. */
static inline uint32_t myl_native_octets_hash(const unsigned char *bytes, size_t length) {
    const uint64_t word_key=0xa0761d6478bd642fULL, state_key=0xe7037ed1a0b428dbULL;
    uint64_t state=0x243f6a8885a308d3ULL^length, hash;
    if (length<=8) {
        uint64_t low=0, high=0;
        if (length>=4) {
            uint32_t first, last;
            memcpy(&first,bytes,4); memcpy(&last,bytes+length-4,4);
            low=first; high=last;
        } else if (length) {
            low=(uint64_t)bytes[0]<<16|(uint64_t)bytes[length>>1]<<8|bytes[length-1];
        }
        hash=myl_native_hash_fold(low^word_key,high^state^state_key);
    } else {
        uint64_t word;
        for (size_t at=0;at+8<length;at+=8) {
            memcpy(&word,bytes+at,8);
            state=myl_native_hash_fold(word^word_key,state^state_key);
        }
        memcpy(&word,bytes+length-8,8);
        hash=myl_native_hash_fold(word^word_key,state^state_key);
    }
    return (uint32_t)(hash^(hash>>32));
}
/* A slice described instead of built: `bytes` octets of a text's payload from
 * octet `offset` on. Generated code keeps one in its frame beside the receiver
 * it ranges over, which it holds as the slice's value so the collector keeps
 * the receiver alive (DICT-RANGE-KEY-1). */
typedef struct {
    size_t offset, bytes;
} myl_native_text_span;
/* The octets `input[start:end]` would hold, clamped exactly as
 * `myl_native_text_slice` clamps its scalar endpoints. Allocates nothing. */
void myl_native_text_range(const myl_native_text *input, int64_t start, int64_t end, myl_native_text_span *);
/* An owned text holding the span's octets of `input`, allocated at arena depth
 * `region` with `input` rooted across the allocation: the key a dictionary
 * stores when a described slice turns out to be a new key. NULL once the
 * budget is exhausted. */
myl_native_text *myl_native_text_piece_at(myl_native_heap *, myl_native_text *input, const myl_native_text_span *, unsigned region);
/* The element descriptor a text object carries in its managed header. A text is
 * a leaf whose payload holds no traced pointer, so this descriptor only names
 * the object for the allocator and the budget. */
extern const myl_native_type myl_native_text_leaf;
/* The UTF-8 payload of a text: the octets co-allocated directly behind an owned
 * text's header, or the range of its owner's that a view reads. Never NULL, and
 * never dereferenced past `bytes`. The address is stable for as long as the
 * text is reachable, because a managed object never moves and a view keeps its
 * owner alive. */
static inline const unsigned char *myl_native_text_storage(const myl_native_text *text) {
    if (text->flags & MYL_TEXT_VIEW) {
        const myl_native_text_view *view = (const myl_native_text_view *)text;
        return (const unsigned char *)(view->owner + 1) + text->hash;
    }
    return (const unsigned char *)(text + 1);
}
/* The owned text whose block holds a text's octets: the text itself unless it
 * is a view. */
static inline const myl_native_text *myl_native_text_owner(const myl_native_text *text) {
    return (text->flags & MYL_TEXT_VIEW) ? ((const myl_native_text_view *)text)->owner : text;
}
/* The same payload address as a real callee, which generated code and a boundary
 * that reads the octets in place call by name. It allocates nothing. */
const unsigned char *myl_native_text_payload(const myl_native_text *);
/* A text of `bytes` payload octets for a constructor to write before it
 * publishes the scalar count with `myl_native_text_publish`. The payload is
 * zeroed, and the value is not a valid text until it is published, so it must
 * not reach generated code in between. NULL once the budget is exhausted. */
myl_native_text *myl_native_text_build(myl_native_heap *, size_t bytes);
/* `myl_native_text_build` for a constructor that already knows the payload's
 * scalar count: a non-ASCII text of at least MYL_TEXT_INDEX_MIN octets is
 * allocated with the position index behind its payload (TEXT-INDEX-1), which
 * `myl_native_text_publish` then initializes. `scalars` must be the count the
 * text is published with. NULL once the budget is exhausted. */
myl_native_text *myl_native_text_build_scalars(myl_native_heap *, size_t bytes, size_t scalars);
/* Publish a built text as `scalars` Unicode scalar values whose payload was
 * written, with `plain` set when every one of them is below 0x80. */
void myl_native_text_publish(myl_native_text *, size_t scalars, int plain);
/* myl_native_text_build with `*keep` rooted across the allocation. */
myl_native_text *myl_native_text_build_keeping(myl_native_heap *, size_t bytes, myl_native_text **keep);
/* Byte offset of scalar `index`, which is `index` itself for ASCII text and the
 * payload's octet count for an index at or past the end. A non-ASCII text
 * answers from the nearest of its ends, its last answer and its sample table
 * (TEXT-INDEX-1), so a loop over the scalars, or over slices of them, costs
 * time linear in the text however it is ordered. */
size_t myl_native_text_offset(const myl_native_text *, size_t index);
/* Scalar index of byte offset `at`, the inverse of myl_native_text_offset. */
size_t myl_native_text_index(const myl_native_text *, size_t at);
#ifdef MYL_TEXT_STEPS
/* Octets the position machinery has examined, counted only in a test build so
 * a test can assert a complexity bound without reading a clock. */
extern size_t myl_native_text_steps;
#endif
/* The Unicode scalar value at scalar `index`, which must be in range. */
uint32_t myl_native_text_point_at(const myl_native_text *, size_t index);
/* Fresh text holding the octets of `input` in `[from, to)`, both of which must
 * begin a scalar. The scalar count is measured over the piece alone, never
 * carried, so cutting a text into pieces costs one pass over it in total. */
myl_native_text *myl_native_text_substring(myl_native_heap *, myl_native_text *, size_t from, size_t to);
/* Octet offset of the first occurrence of a nonempty `needle`, or SIZE_MAX. Both
 * payloads are valid UTF-8, so an octet match begins a scalar in both. */
size_t myl_native_text_find_bytes(const myl_native_text *, const myl_native_text *needle);
/* Offset of the first occurrence of the `count` octets at `needle` inside the
 * `length` octets at `haystack`, or SIZE_MAX; an empty needle occurs at 0. The
 * scan runs in libc's bulk primitives — `memchr` for the first octet, `memmem`
 * once that octet keeps recurring without a match — so a candidate costs no
 * call of its own. Text and byte strings search through this one routine. */
size_t myl_native_octets_find(const unsigned char *haystack, size_t length, const unsigned char *needle, size_t count);
/* Non-overlapping occurrences of a nonempty `needle`, scanned left to right, so
 * `aaa` holds one `aa`; an empty needle or one longer than the haystack has
 * none. It is exactly the number of cuts a separator split makes. */
size_t myl_native_octets_count(const unsigned char *haystack, size_t length, const unsigned char *needle, size_t count);
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
/* Fresh text holding every `step`-th scalar in Python's stepped-slice range, or
 * NULL for a zero step or a refused allocation. A stepped slice gathers scalars,
 * so it cannot read a stride of the UTF-8 payload. */
myl_native_text *myl_native_text_slice_step(myl_native_heap *, myl_native_text *, int64_t start, int64_t stop, int64_t step);
/* `text` itself when it owns its octets; for a view, an owned copy of the view's
 * octets allocated at arena depth `region`, with the view rooted across the
 * allocation. NULL once the budget is exhausted. A dictionary stores its text
 * keys this way, so a stored key's octets are always its header's tail. */
myl_native_text *myl_native_text_own_at(myl_native_heap *, myl_native_text *, unsigned region);
/* A copy of one text inside the heap's current arena depth, payload and all: the
 * arena escape copier clones a text wholesale because its payload holds no
 * pointer to patch. */
myl_native_text *myl_native_text_clone(myl_native_heap *, const myl_native_text *);
myl_native_text *myl_native_text_concat(myl_native_heap *, myl_native_text *, myl_native_text *);
myl_native_text *myl_native_text_at(myl_native_heap *, myl_native_text *, int64_t);
myl_native_text *myl_native_text_slice(myl_native_heap *, myl_native_text *, int64_t, int64_t);
/* TEXT-VIEW-5: clamp the same endpoints as slice; an omitted upper endpoint
 * shares a suffix of at least nine octets independently of the owner ratio.
 * Explicit bounded slices and split pieces retain TEXT-VIEW-3. */
myl_native_text *myl_native_text_tail(myl_native_heap *, myl_native_text *, int64_t, int64_t);
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
