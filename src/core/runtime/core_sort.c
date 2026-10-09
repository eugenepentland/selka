/* S2-F: port of native_collections.c's stable powersort and decorated sort.
   This runtime is independent of the old core; only the algorithm is shared. */
#include <math.h>
typedef struct { size_t size; } s2_sort_element;
typedef struct { size_t length, capacity; uint64_t generation; void *storage; const s2_sort_element *element; } s2_sort_list;
static int s2_sort_block_compare(const myl_block *a, const myl_block *b) {
    size_t n = (size_t)(a->len < b->len ? a->len : b->len);
    int order = memcmp((const unsigned char *)a+SELKA_HEADER, (const unsigned char *)b+SELKA_HEADER, n);
    return order ? order : a->len < b->len ? -1 : a->len > b->len;
}
static int s2_compare_signed(const unsigned char *a, const unsigned char *b, size_t size) {
    int64_t x, y;
    switch (size) {
    case 1: { int8_t l,r; memcpy(&l,a,1); memcpy(&r,b,1); x=l; y=r; break; }
    case 2: { int16_t l,r; memcpy(&l,a,2); memcpy(&r,b,2); x=l; y=r; break; }
    case 4: { int32_t l,r; memcpy(&l,a,4); memcpy(&r,b,4); x=l; y=r; break; }
    default: memcpy(&x,a,8); memcpy(&y,b,8); break;
    }
    return x<y ? -1 : x>y;
}
static int s2_compare_unsigned(const unsigned char *a, const unsigned char *b, size_t size) {
    uint64_t x=0,y=0; memcpy(&x,a,size); memcpy(&y,b,size); return x<y ? -1 : x>y;
}
static void s2_copy_element(void *to, const void *from, size_t size) { memcpy(to,from,size); }
/* `list.sort()` is an adaptive stable merge sort, the shape of CPython's
   listsort without galloping. The list is cut into natural runs; a strictly
   descending run is reversed, and a run shorter than `minrun` is extended by
   insertion sort. Runs are merged in the order the powersort rule picks, so
   the merge tree stays balanced over any mix of run lengths, through one
   scratch buffer of at most half the list: a merge copies the shorter run out
   and merges forward or backward into the space it left.

   Equal elements never pass each other. A reversed run is strictly
   descending, insertion stops at the first element not greater than the one
   it places, a merge first skips the left elements not greater than the right
   run's head and the right elements not less than the left run's tail, and it
   takes the left element on a tie. The order itself is the one the language
   documents: integers by value, binary64 values with every NaN after every
   ordered value and signed zeros tied, text by Unicode scalar value.

   The algorithm is written once, over a `s2_sort_kind`. Each entry point passes a
   constant kind, so after inlining every comparison and move is compiled for
   that element type: merging 64-bit integers or floats is a compare and a few
   conditional selects per element, with no branch to mispredict. The narrower
   integer widths share one generic entry that keeps a per-comparison switch on
   the width. Sorting calls no guest code and allocates nothing managed, so no
   collection can run while text pointers sit in the scratch buffer. */
enum { SORT_I64, SORT_U64, SORT_F64, SORT_TEXT, SORT_GENERIC, SORT_BYTES };
typedef struct { unsigned kind, order; size_t size; unsigned reverse; } s2_sort_kind;
typedef struct { size_t start, length; int power; } s2_sort_run;
/* Runs below this length are extended by insertion sort; `s2_sort_minrun` picks
   a value in [SORT_MINRUN_LIMIT / 2, SORT_MINRUN_LIMIT] that splits the list
   into close to a power of two runs. */
#define SORT_MINRUN_LIMIT 32
/* The powers on the stack strictly increase, so a 64-bit length needs at most
   65 pending runs, the bound CPython's listsort uses; the rest is margin, and
   a full stack would merge its top pair first. */
#define SORT_STACK 96
#define SORT_INLINE static inline __attribute__((always_inline))
SORT_INLINE size_t s2_sort_size(s2_sort_kind kind) {
    return kind.kind == SORT_GENERIC ? kind.size : 8;
}
/* Move one element of a sortable width: 1, 2, 4 or 8 bytes. */
SORT_INLINE void s2_sort_copy(unsigned char *to, const unsigned char *from, size_t size) {
    switch (size) {
    case 1: memcpy(to, from, 1); return;
    case 2: memcpy(to, from, 2); return;
    case 4: memcpy(to, from, 4); return;
    default: memcpy(to, from, 8); return;
    }
}
SORT_INLINE int s2_sort_less(const unsigned char *left, const unsigned char *right, s2_sort_kind kind) {
    if (kind.reverse) { const unsigned char *held=left; left=right; right=held; }
    switch (kind.kind) {
    case SORT_I64: { int64_t a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b; }
    case SORT_U64: { uint64_t a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b; }
    case SORT_F64: { double a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b || (isnan(b) && !isnan(a)); }
    case SORT_TEXT: {
        myl_block *a, *b;
        memcpy(&a, left, sizeof a);
        memcpy(&b, right, sizeof b);
        return s2_sort_block_compare(a, b) < 0;
    }
    case SORT_BYTES: {
        myl_block *a, *b;
        memcpy(&a, left, sizeof a);
        memcpy(&b, right, sizeof b);
        return s2_sort_block_compare(a, b) < 0;
    }
    default: return (kind.order == 0 ? s2_compare_signed(left, right, kind.size) : s2_compare_unsigned(left, right, kind.size)) < 0;
    }
}
/* Length of the natural run that starts at `start`, left ascending: a strictly
   descending run is reversed in place, which cannot reorder equal elements
   because it holds none. */
SORT_INLINE size_t s2_sort_natural_run(unsigned char *base, size_t start, size_t end, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), last = start + 1;
    if (last == end) return 1;
    if (s2_sort_less(base + last * size, base + start * size, kind)) {
        while (last + 1 < end && s2_sort_less(base + (last + 1) * size, base + last * size, kind)) last++;
        unsigned char held[8];
        for (size_t low = start, high = last; low < high; low++, high--) {
            s2_sort_copy(held, base + low * size, size);
            s2_sort_copy(base + low * size, base + high * size, size);
            s2_sort_copy(base + high * size, held, size);
        }
    } else {
        while (last + 1 < end && !s2_sort_less(base + (last + 1) * size, base + last * size, kind)) last++;
    }
    return last - start + 1;
}
/* Extend the ascending run [start, sorted) to [start, end) by stable
   insertion: each element moves left only past elements greater than it. */
SORT_INLINE void s2_sort_insertion(unsigned char *base, size_t start, size_t sorted, size_t end, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind);
    unsigned char held[8];
    for (size_t i = sorted; i < end; i++) {
        if (!s2_sort_less(base + i * size, base + (i - 1) * size, kind)) continue;
        s2_sort_copy(held, base + i * size, size);
        size_t j = i;
        do {
            s2_sort_copy(base + j * size, base + (j - 1) * size, size);
            j--;
        } while (j > start && s2_sort_less(held, base + (j - 1) * size, kind));
        s2_sort_copy(base + j * size, held, size);
    }
}
/* How many leading elements of the ascending `run` are not greater than
   `value`: the place a stable merge gives `value` when it comes from the right. */
SORT_INLINE size_t s2_sort_upper_bound(const unsigned char *run, size_t count, const unsigned char *value, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (s2_sort_less(value, run + middle * size, kind)) high = middle;
        else low = middle + 1;
    }
    return low;
}
/* How many leading elements of the ascending `run` are less than `value`: the
   place a stable merge gives `value` when it comes from the left. */
SORT_INLINE size_t s2_sort_lower_bound(const unsigned char *run, size_t count, const unsigned char *value, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (s2_sort_less(run + middle * size, value, kind)) low = middle + 1;
        else high = middle;
    }
    return low;
}
/* One comparison of two 8-byte elements held in registers. */
SORT_INLINE int s2_sort_less_words(uint64_t left, uint64_t right, s2_sort_kind kind) {
    unsigned char a[8], b[8];
    memcpy(a, &left, 8);
    memcpy(b, &right, 8);
    return s2_sort_less(a, b, kind);
}
/* Merge the adjacent ascending runs [first, middle) and [middle, last). Only
   the stretch the two runs actually interleave over moves; the shorter side of
   it goes to `scratch`, which holds at least half the list.

   For 8-byte elements the bulk of the merge runs while both sides still hold
   two elements: the element after each side's head is loaded before the
   comparison that picks one, so advancing is a pair of selects rather than a
   load that has to wait for the comparison. The element loop finishes the
   last few elements and serves the narrower widths. */
SORT_INLINE void s2_sort_merge(unsigned char *base, size_t first, size_t middle, size_t last, unsigned char *scratch, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind);
    first += s2_sort_upper_bound(base + first * size, middle - first, base + middle * size, kind);
    if (first == middle) return;
    last = middle + s2_sort_lower_bound(base + middle * size, last - middle, base + (middle - 1) * size, kind);
    size_t left = middle - first, right = last - middle;
    /* The first remaining left value exceeds the first right value. The
       last left value is at least as large, so the lower trim retains that
       first right value; both runs are nonempty here. */
    /* Strictly separated runs need only exchange their positions. Keep each
       run's order, and buffer the shorter side in the same reserved scratch.
       Equality must retain the ordinary stable merge: rotating equal boundary
       values would put right-run ties before their earlier left-run peers. */
    if (s2_sort_less(base + (last - 1) * size, base + first * size, kind)) {
        if (left <= right) {
            memcpy(scratch, base + first * size, left * size);
            memmove(base + first * size, base + middle * size, right * size);
            memcpy(base + (first + right) * size, scratch, left * size);
        } else {
            memcpy(scratch, base + middle * size, right * size);
            memmove(base + (first + right) * size, base + first * size, left * size);
            memcpy(base + first * size, scratch, right * size);
        }
        return;
    }
    if (left <= right) {
        /* Forward: the left run waits in scratch, the output never overtakes
           the unread right elements, and whatever of the right run is left
           over is already in place. */
        memcpy(scratch, base + first * size, left * size);
        const unsigned char *a = scratch, *a_end = scratch + left * size;
        const unsigned char *b = base + middle * size, *b_end = base + last * size;
        unsigned char *out = base + first * size;
        while (kind.kind != SORT_GENERIC) {
            size_t a_left = (size_t)(a_end - a) / 8, b_left = (size_t)(b_end - b) / 8;
            size_t steps = a_left < b_left ? a_left : b_left;
            if (steps < 2) break;
            uint64_t x, y;
            memcpy(&x, a, 8);
            memcpy(&y, b, 8);
            for (steps--; steps; steps--) {
                int take_right = s2_sort_less_words(y, x, kind);
                uint64_t chosen = take_right ? y : x, x_next, y_next;
                memcpy(out, &chosen, 8);
                out += 8;
                memcpy(&x_next, a + 8, 8);
                memcpy(&y_next, b + 8, 8);
                a += take_right ? 0 : 8;
                b += take_right ? 8 : 0;
                x = take_right ? x : x_next;
                y = take_right ? y_next : y;
            }
        }
        while (a < a_end && b < b_end) {
            int take_right = s2_sort_less(b, a, kind);
            s2_sort_copy(out, take_right ? b : a, size);
            out += size;
            b += take_right ? size : 0;
            a += take_right ? 0 : size;
        }
        if (a < a_end) memcpy(out, a, (size_t)(a_end - a));
    } else {
        /* Backward: the right run waits in scratch and the larger element of
           each pair goes last, the right one on a tie; whatever of the left
           run is left over is already in place. */
        memcpy(scratch, base + middle * size, right * size);
        const unsigned char *a = base + middle * size, *a_begin = base + first * size;
        const unsigned char *b = scratch + right * size;
        unsigned char *out = base + last * size;
        while (kind.kind != SORT_GENERIC) {
            size_t a_left = (size_t)(a - a_begin) / 8, b_left = (size_t)(b - scratch) / 8;
            size_t steps = a_left < b_left ? a_left : b_left;
            if (steps < 2) break;
            uint64_t x, y;
            memcpy(&x, a - 8, 8);
            memcpy(&y, b - 8, 8);
            for (steps--; steps; steps--) {
                int take_left = s2_sort_less_words(y, x, kind);
                uint64_t chosen = take_left ? x : y, x_next, y_next;
                out -= 8;
                memcpy(out, &chosen, 8);
                memcpy(&x_next, a - 16, 8);
                memcpy(&y_next, b - 16, 8);
                a -= take_left ? 8 : 0;
                b -= take_left ? 0 : 8;
                x = take_left ? x_next : x;
                y = take_left ? y : y_next;
            }
        }
        while (a > a_begin && b > scratch) {
            int take_left = s2_sort_less(b - size, a - size, kind);
            out -= size;
            s2_sort_copy(out, take_left ? a - size : b - size, size);
            a -= take_left ? size : 0;
            b -= take_left ? 0 : size;
        }
        if (b > scratch) memcpy(out - (b - scratch), scratch, (size_t)(b - scratch));
    }
}
/* A run length in [SORT_MINRUN_LIMIT / 2, SORT_MINRUN_LIMIT] such that
   `count / minrun` is a power of two or just under one, as in listsort. */
static size_t s2_sort_minrun(size_t count) {
    size_t low_bits = 0;
    while (count >= SORT_MINRUN_LIMIT) {
        low_bits |= count & 1;
        count >>= 1;
    }
    return count + low_bits;
}
/* The powersort depth of the boundary between the adjacent runs
   [start, start + left) and [start + left, start + left + right) of a list of
   `total` elements: the first bit at which the two runs' midpoints, as
   fractions of the list, differ. */
static int s2_sort_power(size_t start, size_t left, size_t right, size_t total) {
    int power = 0;
    size_t a = 2 * start + left, b = a + left + right;
    for (;;) {
        ++power;
        if (a >= total) {
            a -= total;
            b -= total;
        } else if (b >= total) {
            break;
        }
        a <<= 1;
        b <<= 1;
    }
    return power;
}
SORT_INLINE int s2_sort_elements(unsigned char *base, size_t count, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), minrun = s2_sort_minrun(count);
    unsigned char *scratch = NULL;
    if (count > minrun) {
        scratch = malloc(count / 2 * size);
        if (!scratch) return 0;
    }
    s2_sort_run stack[SORT_STACK];
    size_t depth = 0, start = 0;
    for (;;) {
        /* Power 0 once the input is exhausted, which merges everything left. */
        int power = 0;
        size_t length = 0;
        if (start < count) {
            length = s2_sort_natural_run(base, start, count, kind);
            if (length < minrun) {
                size_t end = count - start < minrun ? count : start + minrun;
                s2_sort_insertion(base, start, start + length, end, kind);
                length = end - start;
            }
            if (depth) power = s2_sort_power(stack[depth - 1].start, stack[depth - 1].length, length, count);
        }
        while (depth > 1 && (stack[depth - 2].power > power || depth == SORT_STACK)) {
            s2_sort_run *left = &stack[depth - 2], *right = &stack[depth - 1];
            s2_sort_merge(base, left->start, right->start, right->start + right->length, scratch, kind);
            left->length += right->length;
            depth--;
        }
        if (start >= count) break;
        if (depth) stack[depth - 1].power = power;
        stack[depth++] = (s2_sort_run){ .start = start, .length = length, .power = 0 };
        start += length;
    }
    free(scratch);
    return 1;
}
static int s2_sort_i64(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_I64, .order = 0, .size = 8 });
}
static int s2_sort_u64(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_U64, .order = 1, .size = 8 });
}
static int s2_sort_f64(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_F64, .order = 2, .size = 8 });
}
static int s2_sort_text(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_TEXT, .order = 3, .size = 8 });
}
static int s2_sort_bytes(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_BYTES, .order = 4, .size = 8 });
}
static int s2_sort_generic(unsigned char *base, size_t count, unsigned order, size_t size) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_GENERIC, .order = order, .size = size });
}

/* `values.sort(key=..., reverse=...)` after the guest has computed every key
   once, in input order, into `keys`: a decorated sort. The keys decide an
   order of positions. When `values` is `source`, one pass of cycle-following
   moves the elements into that order, so the list is sorted in place and
   keeps its identity, length, capacity and generation. Otherwise `values` is
   an empty list with room for them all, and the elements of `source` are
   gathered into it in order: `sorted(xs, key=...)` builds its copy already
   sorted, with no copy to permute afterwards.

   A key is one scalar or a flat tuple of them. Field `i` of `shape` is the
   four bits at `4 + 4 * i`: the low two bits are its kind (signed, unsigned,
   binary64 or text) and the high two its width (8, 4, 2 or 1 bytes); the low
   four bits of `shape` are the field count. Byte `i` of `offsets` is field
   `i`'s offset inside one key.

   A numeric key becomes one order-preserving 64-bit word: a signed integer
   with its sign bit flipped, an unsigned one as it is, and a binary64 value
   with its bits reflected, signed zeros made one and every NaN the largest
   word, so NaNs sort after every ordered value. `reverse` complements the
   word, so the order is the descending one while ties still come in input
   order: reverse is not sort-then-reverse. When every word minus the
   smallest fits above the position bits, the word and its position are packed
   into one integer and sorted by the integer engine; this is the common case
   and it reuses the key list's own storage for the packed words. Keys spread
   wider take two such sorts, 32 bits each. Text keys and tuples sort
   (key, position) entries with a stable merge that compares fields in order.

   Nothing here calls guest code or allocates managed memory, so no collection
   runs while elements sit in the temporary. On an allocation failure it
   returns 0 before any element has moved; the key list may by then hold
   packed words, which the guest never reads again. */
enum { KEY_SIGNED, KEY_UNSIGNED, KEY_FLOAT, KEY_TEXT, KEY_BYTES };
typedef struct { unsigned count; unsigned char kind[8], size[8], offset[8]; } s2_key_shape;
static int s2_key_shape_decode(uint64_t shape, uint64_t offsets, size_t stride, s2_key_shape *out) {
    static const unsigned char widths[4] = { 8, 4, 2, 1 };
    out->count = (unsigned)(shape & 15);
    if (out->count == 0 || out->count > 8) return 0;
    for (unsigned i = 0; i < out->count; i++) {
        unsigned field = (unsigned)(shape >> (4 + 4 * i)) & 15;
        /* Nibble 7 used to be invalid text/width4. Preserve every old code. */
        out->kind[i] = field == 7 ? KEY_BYTES : (unsigned char)(field & 3);
        out->size[i] = field == 7 ? 8 : widths[field >> 2];
        out->offset[i] = (unsigned char)(offsets >> (8 * i));
        if ((out->kind[i] == KEY_FLOAT || out->kind[i] == KEY_TEXT) && out->size[i] != 8) return 0;
        if ((size_t)out->offset[i] + out->size[i] > stride) return 0;
    }
    return 1;
}
/* One numeric key field as a word whose unsigned order is the key order. */
static inline uint64_t s2_key_word(const unsigned char *at, unsigned kind, unsigned size) {
    if (kind == KEY_FLOAT) {
        double value;
        memcpy(&value, at, 8);
        if (isnan(value)) return UINT64_MAX;
        if (value == 0) value = 0;
        uint64_t bits;
        memcpy(&bits, &value, 8);
        return bits >> 63 ? ~bits : bits | (UINT64_C(1) << 63);
    }
    if (kind == KEY_SIGNED) {
        int64_t value;
        switch (size) {
        case 1: { int8_t x; memcpy(&x, at, 1); value = x; break; }
        case 2: { int16_t x; memcpy(&x, at, 2); value = x; break; }
        case 4: { int32_t x; memcpy(&x, at, 4); value = x; break; }
        default: memcpy(&value, at, 8); break;
        }
        return (uint64_t)value ^ (UINT64_C(1) << 63);
    }
    switch (size) {
    case 1: { uint8_t x; memcpy(&x, at, 1); return x; }
    case 2: { uint16_t x; memcpy(&x, at, 2); return x; }
    case 4: { uint32_t x; memcpy(&x, at, 4); return x; }
    default: { uint64_t x; memcpy(&x, at, 8); return x; }
    }
}
/* Three-way comparison of key field `field` of two keys. */
static inline int s2_key_field_compare(const unsigned char *left, const unsigned char *right, const s2_key_shape *shape, unsigned field) {
    const unsigned char *a = left + shape->offset[field], *b = right + shape->offset[field];
    if (shape->kind[field] == KEY_TEXT) {
        myl_block *x, *y;
        memcpy(&x, a, sizeof x);
        memcpy(&y, b, sizeof y);
        int order = s2_sort_block_compare(x, y);
        return order < 0 ? -1 : order > 0;
    }
    if (shape->kind[field] == KEY_BYTES) {
        myl_block *x, *y;
        memcpy(&x, a, sizeof x);
        memcpy(&y, b, sizeof y);
        return s2_sort_block_compare(x, y);
    }
    uint64_t x = s2_key_word(a, shape->kind[field], shape->size[field]);
    uint64_t y = s2_key_word(b, shape->kind[field], shape->size[field]);
    return x < y ? -1 : x > y;
}
/* How far ahead along a cycle the permutation prefetches the element it will
   move next. */
#define KEYED_LOOKAHEAD 8
/* Move every element into the slot `order` names for it: slot `i` receives
   the element at `order[i]`. Each cycle is followed once and marked done by
   setting `order[j] = j`, through one element-sized temporary.

   Following a cycle is a chain of dependent loads, so it runs at memory
   latency unless the next elements are already on their way. The positions
   are first narrowed to 32 bits in place, which halves the table the chain
   walks and keeps more of it in cache, and a second cursor runs
   KEYED_LOOKAHEAD steps ahead on the same cycle, prefetching the element each
   step will read. */
static void s2_keyed_permute(s2_sort_list *values, uint64_t *wide, size_t count, unsigned char *held) {
    size_t size = values->element->size;
    unsigned char *base = values->storage;
    if (size == 0) return;
    uint32_t *order = (uint32_t *)wide;
    if (count <= UINT32_MAX) {
        /* Entry `i` is read at byte 8i before it is written at byte 4i. */
        for (size_t i = 0; i < count; i++) order[i] = (uint32_t)wide[i];
    }
    for (size_t i = 0; i < count; i++) {
        size_t first = count <= UINT32_MAX ? order[i] : (size_t)wide[i];
        if (first == i) continue;
        s2_copy_element(held, base + i * size, size);
        size_t j = i, ahead = i;
        for (int step = 0; step < KEYED_LOOKAHEAD && (step == 0 || ahead != i); step++) {
            ahead = count <= UINT32_MAX ? order[ahead] : (size_t)wide[ahead];
            __builtin_prefetch(base + ahead * size);
        }
        for (;;) {
            size_t k;
            if (count <= UINT32_MAX) {
                k = order[j];
                order[j] = (uint32_t)j;
            } else {
                k = (size_t)wide[j];
                wide[j] = j;
            }
            if (k == i) {
                s2_copy_element(base + j * size, held, size);
                break;
            }
            if (ahead != i) {
                ahead = count <= UINT32_MAX ? order[ahead] : (size_t)wide[ahead];
                __builtin_prefetch(base + ahead * size);
            }
            s2_copy_element(base + j * size, base + k * size, size);
            j = k;
        }
    }
}
/* Where the ordered elements go: back into `source` itself along the
   permutation's cycles (an in-place sort, through `held`), or gathered in
   order from `source` into the empty list `values` (a sorted copy). */
typedef struct { s2_sort_list *values; const s2_sort_list *source; unsigned char *held; } s2_keyed_target;
static void s2_keyed_place(const s2_keyed_target *target, uint64_t *order, size_t count) {
    if (target->values == target->source) {
        s2_keyed_permute(target->values, order, count, target->held);
        return;
    }
    size_t size = target->source->element->size;
    unsigned char *out = target->values->storage;
    const unsigned char *in = target->source->storage;
    for (size_t i = 0; i < count; i++) s2_copy_element(out + i * size, in + (size_t)order[i] * size, size);
    target->values->length = count;
    target->values->generation++;
}
/* Move every element to the slot `dest` names for it: the element at `i`
   goes to `dest[i]`. In place this follows each cycle once, carrying one
   element in `held` and marking each handled position `dest[p] = p`, with the
   same narrowed table and lookahead prefetch as s2_keyed_permute; for a copy it
   scatters the elements into the empty target. */
static void s2_keyed_place_dest(const s2_keyed_target *target, uint64_t *wide, size_t count) {
    size_t size = target->source->element->size;
    if (target->values != target->source) {
        unsigned char *out = target->values->storage;
        const unsigned char *in = target->source->storage;
        for (size_t i = 0; i < count; i++) s2_copy_element(out + (size_t)wide[i] * size, in + i * size, size);
        target->values->length = count;
        target->values->generation++;
        return;
    }
    unsigned char *base = target->values->storage, *held = target->held;
    if (size == 0) return;
    /* count <= UINT32_MAX here: the counting path requires it. */
    uint32_t *dest = (uint32_t *)wide;
    for (size_t i = 0; i < count; i++) dest[i] = (uint32_t)wide[i];
    unsigned char *swap = held + size;
    for (size_t i = 0; i < count; i++) {
        if (dest[i] == i) continue;
        s2_copy_element(held, base + i * size, size);
        size_t p = i, ahead = i;
        for (int step = 0; step < KEYED_LOOKAHEAD && (step == 0 || ahead != i); step++) {
            ahead = dest[ahead];
            __builtin_prefetch(base + ahead * size);
        }
        for (;;) {
            size_t d = dest[p];
            dest[p] = (uint32_t)p;
            if (d == i) {
                s2_copy_element(base + i * size, held, size);
                break;
            }
            if (ahead != i) {
                ahead = dest[ahead];
                __builtin_prefetch(base + ahead * size);
            }
            s2_copy_element(swap, base + d * size, size);
            s2_copy_element(base + d * size, held, size);
            s2_copy_element(held, swap, size);
            p = d;
        }
    }
}
/* A single numeric key whose words span fewer values than there are
   elements: a stable counting sort. One pass counts each key, a prefix sum
   turns the counts into first slots, and a second pass gives each element,
   in input order, the next slot of its key — so equal keys keep input order
   without any comparison. */
static int s2_keyed_count(const s2_keyed_target *target, s2_sort_list *keys, const s2_key_shape *shape, uint64_t flip, uint64_t low, uint64_t span) {
    size_t count = target->source->length, stride = keys->element->size;
    const unsigned char *rows = keys->storage;
    unsigned kind = shape->kind[0], size = shape->size[0], offset = shape->offset[0];
    uint32_t *slots = calloc((size_t)span + 1, sizeof *slots);
    if (!slots) return 0;
    for (size_t i = 0; i < count; i++) slots[(s2_key_word(rows + i * stride + offset, kind, size) ^ flip) - low]++;
    uint32_t next = 0;
    for (uint64_t b = 0; b <= span; b++) {
        uint32_t here = slots[b];
        slots[b] = next;
        next += here;
    }
    int own = stride == 8 && offset == 0 && keys != target->values && keys != target->source;
    uint64_t *dest = own ? (uint64_t *)keys->storage : malloc(count * 8);
    if (!dest) {
        free(slots);
        return 0;
    }
    for (size_t i = 0; i < count; i++) dest[i] = slots[(s2_key_word(rows + i * stride + offset, kind, size) ^ flip) - low]++;
    free(slots);
    s2_keyed_place_dest(target, dest, count);
    if (!own) free(dest);
    return 1;
}
typedef struct { uint64_t word; uint64_t position; } s2_keyed_entry;
typedef struct { const unsigned char *keys; size_t stride; const s2_key_shape *shape; unsigned reverse; } s2_keyed_order;
/* Whether entry `a` goes strictly before entry `b`. A single text key is
   carried in the entry itself; any other key is read from its row. */
static inline int s2_keyed_less(const s2_keyed_entry *a, const s2_keyed_entry *b, const s2_keyed_order *by) {
    const s2_keyed_entry *x = by->reverse ? b : a, *y = by->reverse ? a : b;
    if (by->shape->count == 1 && by->shape->kind[0] == KEY_TEXT) {
        myl_block *p, *q;
        memcpy(&p, &x->word, sizeof p);
        memcpy(&q, &y->word, sizeof q);
        return s2_sort_block_compare(p, q) < 0;
    }
    if (by->shape->count == 1 && by->shape->kind[0] == KEY_BYTES) {
        myl_block *p, *q;
        memcpy(&p, &x->word, sizeof p);
        memcpy(&q, &y->word, sizeof q);
        return s2_sort_block_compare(p, q) < 0;
    }
    const unsigned char *left = by->keys + (size_t)x->position * by->stride;
    const unsigned char *right = by->keys + (size_t)y->position * by->stride;
    for (unsigned field = 0; field < by->shape->count; field++) {
        int order = s2_key_field_compare(left, right, by->shape, field);
        if (order) return order < 0;
    }
    return 0;
}
/* Stable bottom-up merge of entries: insertion-sorted blocks of 16, then
   passes that merge adjacent blocks between `entries` and `spare`, taking
   the left entry on a tie. Returns the array holding the result. */
static s2_keyed_entry *s2_keyed_merge_sort(s2_keyed_entry *entries, s2_keyed_entry *spare, size_t count, const s2_keyed_order *by) {
    for (size_t start = 0; start < count; start += 16) {
        size_t end = count - start < 16 ? count : start + 16;
        for (size_t i = start + 1; i < end; i++) {
            s2_keyed_entry held = entries[i];
            size_t j = i;
            while (j > start && s2_keyed_less(&held, &entries[j - 1], by)) {
                entries[j] = entries[j - 1];
                j--;
            }
            entries[j] = held;
        }
    }
    s2_keyed_entry *from = entries, *to = spare;
    for (size_t width = 16; width < count; width *= 2) {
        for (size_t start = 0; start < count; start += 2 * width) {
            size_t middle = count - start < width ? count : start + width;
            size_t end = count - middle < width ? count : middle + width;
            size_t a = start, b = middle, out = start;
            while (a < middle && b < end) to[out++] = s2_keyed_less(&from[b], &from[a], by) ? from[b++] : from[a++];
            while (a < middle) to[out++] = from[a++];
            while (b < end) to[out++] = from[b++];
        }
        s2_keyed_entry *swap = from;
        from = to;
        to = swap;
    }
    return from;
}
static int s2_keyed_sort_entries(const s2_keyed_target *target, const s2_sort_list *keys, const s2_key_shape *shape, unsigned reverse) {
    size_t count = target->source->length, stride = keys->element->size;
    if (count > SIZE_MAX / (2 * sizeof(s2_keyed_entry))) return 0;
    s2_keyed_entry *entries = malloc(2 * count * sizeof *entries);
    if (!entries) return 0;
    const unsigned char *rows = keys->storage;
    for (size_t i = 0; i < count; i++) {
        entries[i].position = i;
        entries[i].word = 0;
        if (shape->count == 1 && (shape->kind[0] == KEY_TEXT || shape->kind[0] == KEY_BYTES)) memcpy(&entries[i].word, rows + i * stride + shape->offset[0], 8);
    }
    s2_keyed_order by = { .keys = rows, .stride = stride, .shape = shape, .reverse = reverse };
    s2_keyed_entry *sorted = s2_keyed_merge_sort(entries, entries + count, count, &by);
    uint64_t *order = (uint64_t *)entries;
    /* Entry `i` is 16 bytes and position `i` is 8, so compacting forward
       never overwrites an entry not yet read, whichever half holds them. */
    for (size_t i = 0; i < count; i++) order[i] = sorted[i].position;
    s2_keyed_place(target, order, count);
    free(entries);
    return 1;
}
/* One numeric key: pack `(word - low) << bits | position` into one integer
   per element when that fits, else sort by the low 32 bits of the word and
   then, stably, by the high 32 bits. */
static int s2_keyed_sort_words(const s2_keyed_target *target, s2_sort_list *keys, const s2_key_shape *shape, unsigned reverse) {
    size_t count = target->source->length, stride = keys->element->size;
    const unsigned char *rows = keys->storage;
    unsigned kind = shape->kind[0], size = shape->size[0], offset = shape->offset[0];
    uint64_t flip = reverse ? UINT64_MAX : 0, low = UINT64_MAX, high = 0;
    for (size_t i = 0; i < count; i++) {
        uint64_t word = s2_key_word(rows + i * stride + offset, kind, size) ^ flip;
        low = word < low ? word : low;
        high = word > high ? word : high;
    }
    if (count <= UINT32_MAX && high - low < count) return s2_keyed_count(target, keys, shape, flip, low, high - low);
    unsigned bits = 1;
    while (bits < 63 && ((uint64_t)1 << bits) < count) bits++;
    uint64_t mask = ((uint64_t)1 << bits) - 1;
    if (((high - low) >> (64 - bits)) == 0) {
        /* The words replace the keys one for one, so they are written into
           the key list's storage when it has 8-byte keys of its own, not the
           elements themselves. */
        int own = stride == 8 && offset == 0 && keys != target->values && keys != target->source;
        uint64_t *words = own ? (uint64_t *)keys->storage : malloc(count * 8);
        if (!words) return 0;
        for (size_t i = 0; i < count; i++) words[i] = ((s2_key_word(rows + i * stride + offset, kind, size) ^ flip) - low) << bits | i;
        if (!s2_sort_u64((unsigned char *)words, count)) {
            if (!own) free(words);
            return 0;
        }
        for (size_t i = 0; i < count; i++) words[i] &= mask;
        s2_keyed_place(target, words, count);
        if (!own) free(words);
        return 1;
    }
    if (bits > 32) return s2_keyed_sort_entries(target, keys, shape, reverse);
    uint64_t *by_low = malloc(count * 8), *by_high = malloc(count * 8);
    if (!by_low || !by_high) {
        free(by_low);
        free(by_high);
        return 0;
    }
    for (size_t i = 0; i < count; i++) by_low[i] = ((s2_key_word(rows + i * stride + offset, kind, size) ^ flip) & UINT32_MAX) << bits | i;
    int sorted = s2_sort_u64((unsigned char *)by_low, count);
    for (size_t rank = 0; sorted && rank < count; rank++) {
        uint64_t word = s2_key_word(rows + (by_low[rank] & mask) * stride + offset, kind, size) ^ flip;
        by_high[rank] = (word >> 32) << bits | rank;
    }
    if (sorted) sorted = s2_sort_u64((unsigned char *)by_high, count);
    if (sorted) {
        for (size_t i = 0; i < count; i++) by_high[i] = by_low[by_high[i] & mask] & mask;
        s2_keyed_place(target, by_high, count);
    }
    free(by_low);
    free(by_high);
    return sorted;
}
static int s2_sort_list_sort_keyed(s2_sort_list *values, s2_sort_list *source, s2_sort_list *keys, uint64_t shape, uint64_t offsets, uint64_t reverse) {
    s2_key_shape decoded;
    if (!source || !keys || keys->length != source->length) return 0;
    size_t count = source->length, size = source->element->size;
    /* A sorted copy gathers into an empty list with room for every element. */
    if (values != source && (values->length != 0 || values->capacity < count || values->element->size != size)) return 0;
    if (!s2_key_shape_decode(shape, offsets, keys->element->size, &decoded)) return 0;
    if (count < 2) {
        uint64_t first = 0;
        if (values != source && count) s2_keyed_place(&(s2_keyed_target){ .values = values, .source = source }, &first, 1);
        return 1;
    }
    /* Two element-sized temporaries: the one carried along a cycle, and the
       one it is exchanged through. */
    unsigned char inline_held[128];
    unsigned char *held = values != source || 2 * size <= sizeof inline_held ? inline_held : malloc(2 * size);
    if (!held) return 0;
    s2_keyed_target target = { .values = values, .source = source, .held = held };
    int done = decoded.count == 1 && decoded.kind[0] != KEY_TEXT && decoded.kind[0] != KEY_BYTES
        ? s2_keyed_sort_words(&target, keys, &decoded, reverse != 0)
        : s2_keyed_sort_entries(&target, keys, &decoded, reverse != 0);
    if (held != inline_held) free(held);
    return done;
}
/* Consumes the unique list chosen by own.zig; no count traffic while sorting. */
myl_block *myl_core_s2_sort_in_place(myl_block *list, uint64_t code, bool reverse) {
    size_t size=code>>8, count=(size_t)list->len;
    unsigned order=(unsigned)(code&255);
    int ok;
    unsigned char *base=block_data(list);
    if (reverse) {
        unsigned type=order==2 ? SORT_F64 : order==3 ? SORT_TEXT : order==4 ? SORT_BYTES : size==8 ? (order==0 ? SORT_I64 : SORT_U64) : SORT_GENERIC;
        ok=s2_sort_elements(base,count,(s2_sort_kind){ .kind=type,.order=order,.size=size,.reverse=1 });
    } else if (order==2) ok=s2_sort_f64(base,count);
    else if (order==3) ok=s2_sort_text(base,count);
    else if (order==4) ok=s2_sort_bytes(base,count);
    else if (size==8) ok=order==0 ? s2_sort_i64(base,count) : s2_sort_u64(base,count);
    else ok=s2_sort_generic(base,count,order,size);
    if (!ok) _Exit(1);
    return list;
}

/* Borrow source and keys, return one sorted owning copy. Never mutate borrowed keys. */
myl_block *myl_core_s2_sort_keyed(myl_block *source, myl_block *keys, uint64_t shape, uint64_t offsets, bool reverse, uint64_t strides) {
    size_t size=(size_t)(strides&UINT32_MAX), key_size=(size_t)(strides>>32);
    myl_block *values=myl_core_list_copy(source,(int64_t)size);
    myl_block *key_copy=myl_core_list_copy(keys,(int64_t)key_size);
    s2_sort_element element={size}, key_element={key_size};
    /* The clone already owns exactly the source's reference multiset. Gather
       its permutation straight from source; cycle moves would copy records
       repeatedly and needlessly reserve two element temporaries. */
    s2_sort_list v={ 0,(size_t)values->cap,0,block_data(values),&element };
    s2_sort_list s={ (size_t)source->len,(size_t)source->cap,0,block_data(source),&element };
    s2_sort_list k={ (size_t)key_copy->len,(size_t)key_copy->cap,0,block_data(key_copy),&key_element };
    int ok=s2_sort_list_sort_keyed(&v,&s,&k,shape,offsets,reverse);
    /* The numeric engine overwrites keys with packed words: release their
       original managed references only on the untouched text/tuple path. */
    myl_core_release(key_copy);
    if (!ok) _Exit(1);
    return values;
}
