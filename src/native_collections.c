#include "native_collections.h"
#include "native_equal.h"
#include "native_text.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
static const myl_native_type pointer_type = {
    .size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER
};
static const myl_native_field list_fields[] = {
    { .offset = offsetof(myl_native_list, storage), .type = &pointer_type }
};
static const myl_native_type list_type = {
    .size = sizeof(myl_native_list), .alignment = _Alignof(myl_native_list),
    .kind = MYL_NATIVE_RECORD, .fields = list_fields, .field_count = 1
};
myl_native_list *myl_native_list_new(myl_native_heap *heap, const myl_native_type *element, size_t capacity) {
    if (!element) return NULL;
    myl_native_list *list = myl_native_heap_alloc(heap, &list_type, 1);
    if (!list) return NULL;
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    list->element = element;
    if (capacity) {
        list->storage = myl_native_heap_alloc(heap, element, capacity);
        if (!list->storage) {
            myl_native_root_pop(heap, &root);
            return NULL;
        }
    }
    list->capacity = capacity;
    myl_native_root_pop(heap, &root);
    return list;
}
/* Copy one element whose size is only known at run time. Most element types are
   a word or a small record, and a plain `memcpy` call for those dominates every
   list operation; the switch lets the compiler emit the moves inline for the
   sizes the language actually uses and keeps the call only for the rest. */
static inline __attribute__((always_inline)) void copy_element(void *destination, const void *source, size_t size) {
    switch (size) {
    case 1: *(unsigned char *)destination=*(const unsigned char *)source; return;
    case 2: memcpy(destination,source,2); return;
    case 4: memcpy(destination,source,4); return;
    case 8: memcpy(destination,source,8); return;
    case 16: memcpy(destination,source,16); return;
    case 24: memcpy(destination,source,24); return;
    case 32: memcpy(destination,source,32); return;
    case 40: memcpy(destination,source,40); return;
    case 56: memcpy(destination,source,56); return;
    case 64: memcpy(destination,source,64); return;
    default: memcpy(destination,source,size); return;
    }
}
/* Whether `address` names a byte inside the `bytes` at `block`: the one value an
   in-place growth must not be handed, because the reservation it points into is
   the one about to move. */
static int elementWithin(const void *address, const void *block, size_t bytes) {
    uintptr_t at = (uintptr_t)address, start = (uintptr_t)block;
    return block && at >= start && at - start < bytes;
}
int myl_native_list_append(myl_native_heap *heap, myl_native_list *list, const void *value) {    if (list->generation == UINT64_MAX) return 0;
    /* Room already reserved: nothing here can allocate, so nothing can collect
       and neither the list nor the value needs a root record for this call. */
    if (list->length < list->capacity) {
        copy_element((unsigned char *)list->storage + list->length * list->element->size, value, list->element->size);
        list->length++;
        list->generation++;
        return 1;
    }
    myl_native_root owner_root, value_root;
    myl_native_root_push(heap, &owner_root, &list, &pointer_type);
    myl_native_root_push(heap, &value_root, (void *)value, list->element);
    size_t capacity = list->capacity < 4 ? 4 : list->capacity;
    if (list->capacity >= 4) {
        if (capacity > SIZE_MAX / 2) goto failure;
        capacity *= 2;
    }
    /* Grown backing joins the list's own arena, so an append performed inside
       a younger arena never leaves an older list with storage that is about
       to be bulk released.

       A backing big enough to be its own one-slot segment is extended in place
       instead: the elements it already holds are exactly the ones the copy would
       rewrite and the pages behind them exactly the ones it would fault a second
       time for. Nothing outside the list holds a pointer into that backing — the
       element reads, the index, the sort and the dictionary entries all derive
       their addresses from the header on every use — so only a value already
       inside it has to keep its distance rather than its address, and that value
       is what the ordinary allocate-and-copy path below still serves. */
    void *storage = NULL;
    if (!elementWithin(value, list->storage, list->length * list->element->size))
        storage = myl_native_heap_extend(heap, list->storage, capacity);
    if (!storage) {
        storage = myl_native_heap_alloc_at(heap, list->element, capacity, myl_native_object_region(heap, list));
        if (!storage) goto failure;
        if (list->length) memcpy(storage, list->storage, list->length * list->element->size);
    }
    /* value may point into old backing; copy before unlinking that backing. */
    copy_element((unsigned char *)storage + list->length * list->element->size, value, list->element->size);
    list->storage = storage;
    list->capacity = capacity;
    list->length++;
    list->generation++;
    myl_native_root_pop(heap, &value_root);
    myl_native_root_pop(heap, &owner_root);
    return 1;
failure:
    myl_native_root_pop(heap, &value_root);
    myl_native_root_pop(heap, &owner_root);
    return 0;
}
int myl_native_list_append_scalar(myl_native_heap *heap, myl_native_list *list, uint64_t value) {
    /* The element lives in the low bytes of `value` on this little-endian
       target, so one stack slot of eight bytes is the value pointer the shared
       grow path copies from. Emitted code has already answered the room case. */
    return myl_native_list_append(heap, list, &value);
}
int myl_native_list_get(const myl_native_list *list, size_t index, void *output) {
    if (index >= list->length) return 0;
    copy_element(output, (const unsigned char *)list->storage + index * list->element->size, list->element->size);
    return 1;
}
int myl_native_list_set(myl_native_list *list, size_t index, const void *value) {
    if (index >= list->length) return 0;
    copy_element((unsigned char *)list->storage + index * list->element->size, value, list->element->size);
    return 1;
}
int myl_native_list_pop(myl_native_list *list, void *output) {
    if (!list->length || list->generation == UINT64_MAX) return 0;
    list->length--;
    unsigned char *slot = (unsigned char *)list->storage + list->length * list->element->size;
    copy_element(output, slot, list->element->size);
    memset(slot, 0, list->element->size);
    list->generation++;
    return 1;
}
int myl_native_list_clear(myl_native_list *list) {
    if (!list->length) return 1;
    if (list->generation == UINT64_MAX) return 0;
    memset(list->storage, 0, list->length * list->element->size);
    list->length = 0;
    list->generation++;
    return 1;
}
/* Grow backing storage for an insertion. The caller roots the list because the
   allocation may trigger collection. Existing elements keep their order. */
static int reserve_for_insert(myl_native_heap *heap, myl_native_list *list, size_t needed) {
    if (needed <= list->capacity) return 1;
    size_t capacity = list->capacity < 4 ? 4 : list->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) return 0;
        capacity *= 2;
    }
    void *storage = myl_native_heap_alloc_at(heap, list->element, capacity, myl_native_object_region(heap, list));
    if (!storage) return 0;
    if (list->length) memcpy(storage, list->storage, list->length * list->element->size);
    list->storage = storage;
    list->capacity = capacity;
    return 1;
}
int myl_native_list_extend(myl_native_heap *heap, myl_native_list *list, const myl_native_list *other) {
    if (!list || !other || other->element != list->element) return 0;
    size_t count = other->length;
    for (size_t i = 0; i < count; i++) {
        const unsigned char *storage = other->storage;
        if (!myl_native_list_append(heap, list, storage + i * other->element->size)) return 0;
    }
    return 1;
}
int myl_native_list_insert(myl_native_heap *heap, myl_native_list *list, int64_t index, const void *value) {
    if (!list || list->generation == UINT64_MAX) return 0;
    size_t at;
    if (index < 0) {
        int64_t from_end = (int64_t)list->length + index;
        at = from_end < 0 ? 0 : (size_t)from_end;
    } else {
        at = (uint64_t)index > list->length ? list->length : (size_t)index;
    }
    myl_native_root owner_root, value_root;
    myl_native_root_push(heap, &owner_root, &list, &pointer_type);
    myl_native_root_push(heap, &value_root, (void *)value, list->element);
    ptrdiff_t offset = -1;
    if ((const unsigned char *)value >= (const unsigned char *)list->storage &&
        (const unsigned char *)value < (const unsigned char *)list->storage + list->length * list->element->size) {
        offset = ((const unsigned char *)value - (const unsigned char *)list->storage) / list->element->size;
    }
    if (!reserve_for_insert(heap, list, list->length + 1)) {
        myl_native_root_pop(heap, &value_root);
        myl_native_root_pop(heap, &owner_root);
        return 0;
    }
    unsigned char *storage = list->storage;
    size_t size = list->element->size;
    const unsigned char *source = offset < 0 ? (const unsigned char *)value : storage + (size_t)offset * size;
    if (at < list->length) memmove(storage + (at + 1) * size, storage + at * size, (list->length - at) * size);
    /* A value read from this list moved with the shifted tail. */
    if (offset >= 0 && (size_t)offset >= at) source = storage + ((size_t)offset + 1) * size;
    memcpy(storage + at * size, source, size);
    list->length++;
    list->generation++;
    myl_native_root_pop(heap, &value_root);
    myl_native_root_pop(heap, &owner_root);
    return 1;
}
int myl_native_list_index(const myl_native_list *list, const void *value, int64_t *output) {
    for (size_t i = 0; i < list->length; i++) {
        int equal = myl_native_equal(list->element, (const unsigned char *)list->storage + i * list->element->size, value);
        if (equal < 0) return -1;
        if (equal) {
            *output = (int64_t)i;
            return 1;
        }
    }
    return 0;
}
int myl_native_list_remove(myl_native_list *list, const void *value) {
    int64_t at = 0;
    int found = myl_native_list_index(list, value, &at);
    if (found != 1) return found;
    if (list->generation == UINT64_MAX) return -1;
    unsigned char *storage = list->storage;
    size_t size = list->element->size;
    size_t index = (size_t)at;
    size_t moved = list->length - index - 1;
    if (moved) memmove(storage + index * size, storage + (index + 1) * size, moved * size);
    memset(storage + (list->length - 1) * size, 0, size);
    list->length--;
    list->generation++;
    return 1;
}
int myl_native_list_pop_at(myl_native_list *list, int64_t index, void *output) {
    if (!list->length || list->generation == UINT64_MAX) return 0;
    size_t at;
    if (index < 0) {
        int64_t from_end = (int64_t)list->length + index;
        if (from_end < 0) return 0;
        at = (size_t)from_end;
    } else {
        if ((uint64_t)index >= list->length) return 0;
        at = (size_t)index;
    }
    unsigned char *storage = list->storage;
    size_t size = list->element->size;
    memcpy(output, storage + at * size, size);
    size_t moved = list->length - at - 1;
    if (moved) memmove(storage + at * size, storage + (at + 1) * size, moved * size);
    memset(storage + (list->length - 1) * size, 0, size);
    list->length--;
    list->generation++;
    return 1;
}
void myl_native_list_reverse(myl_native_list *list) {
    unsigned char *storage = list->storage;
    size_t size = list->element->size;
    for (size_t i = 0; i < list->length / 2; i++) {
        unsigned char *left = storage + i * size;
        unsigned char *right = storage + (list->length - 1 - i) * size;
        for (size_t byte = 0; byte < size; byte++) {
            unsigned char swap = left[byte];
            left[byte] = right[byte];
            right[byte] = swap;
        }
    }
}
static int compare_signed(const void *left, const void *right, size_t size) {
    int64_t a = 0, b = 0;
    switch (size) {
        case 1: { int8_t x, y; memcpy(&x, left, 1); memcpy(&y, right, 1); a = x; b = y; break; }
        case 2: { int16_t x, y; memcpy(&x, left, 2); memcpy(&y, right, 2); a = x; b = y; break; }
        case 4: { int32_t x, y; memcpy(&x, left, 4); memcpy(&y, right, 4); a = x; b = y; break; }
        default: memcpy(&a, left, 8); memcpy(&b, right, 8); break;
    }
    return a < b ? -1 : a > b ? 1 : 0;
}
static int compare_unsigned(const void *left, const void *right, size_t size) {
    uint64_t a = 0, b = 0;
    switch (size) {
        case 1: { uint8_t x, y; memcpy(&x, left, 1); memcpy(&y, right, 1); a = x; b = y; break; }
        case 2: { uint16_t x, y; memcpy(&x, left, 2); memcpy(&y, right, 2); a = x; b = y; break; }
        case 4: { uint32_t x, y; memcpy(&x, left, 4); memcpy(&y, right, 4); a = x; b = y; break; }
        default: memcpy(&a, left, 8); memcpy(&b, right, 8); break;
    }
    return a < b ? -1 : a > b ? 1 : 0;
}
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

   The algorithm is written once, over a `sort_kind`. Each entry point passes a
   constant kind, so after inlining every comparison and move is compiled for
   that element type: merging 64-bit integers or floats is a compare and a few
   conditional selects per element, with no branch to mispredict. The narrower
   integer widths share one generic entry that keeps a per-comparison switch on
   the width. Sorting calls no guest code and allocates nothing managed, so no
   collection can run while text pointers sit in the scratch buffer. */
enum { SORT_I64, SORT_U64, SORT_F64, SORT_TEXT, SORT_GENERIC };
typedef struct { unsigned kind, order; size_t size; } sort_kind;
typedef struct { size_t start, length; int power; } sort_run;
/* Runs below this length are extended by insertion sort; `sort_minrun` picks
   a value in [SORT_MINRUN_LIMIT / 2, SORT_MINRUN_LIMIT] that splits the list
   into close to a power of two runs. */
#define SORT_MINRUN_LIMIT 32
/* The powers on the stack strictly increase, so a 64-bit length needs at most
   65 pending runs, the bound CPython's listsort uses; the rest is margin, and
   a full stack would merge its top pair first. */
#define SORT_STACK 96
#define SORT_INLINE static inline __attribute__((always_inline))
SORT_INLINE size_t sort_size(sort_kind kind) {
    return kind.kind == SORT_GENERIC ? kind.size : 8;
}
/* Move one element of a sortable width: 1, 2, 4 or 8 bytes. */
SORT_INLINE void sort_copy(unsigned char *to, const unsigned char *from, size_t size) {
    switch (size) {
    case 1: memcpy(to, from, 1); return;
    case 2: memcpy(to, from, 2); return;
    case 4: memcpy(to, from, 4); return;
    default: memcpy(to, from, 8); return;
    }
}
SORT_INLINE int sort_less(const unsigned char *left, const unsigned char *right, sort_kind kind) {
    switch (kind.kind) {
    case SORT_I64: { int64_t a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b; }
    case SORT_U64: { uint64_t a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b; }
    case SORT_F64: { double a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b || (isnan(b) && !isnan(a)); }
    case SORT_TEXT: {
        myl_native_text *a, *b;
        memcpy(&a, left, sizeof a);
        memcpy(&b, right, sizeof b);
        return myl_native_text_compare(a, b) < 0;
    }
    default: return (kind.order == 0 ? compare_signed(left, right, kind.size) : compare_unsigned(left, right, kind.size)) < 0;
    }
}
/* Length of the natural run that starts at `start`, left ascending: a strictly
   descending run is reversed in place, which cannot reorder equal elements
   because it holds none. */
SORT_INLINE size_t sort_natural_run(unsigned char *base, size_t start, size_t end, sort_kind kind) {
    size_t size = sort_size(kind), last = start + 1;
    if (last == end) return 1;
    if (sort_less(base + last * size, base + start * size, kind)) {
        while (last + 1 < end && sort_less(base + (last + 1) * size, base + last * size, kind)) last++;
        unsigned char held[8];
        for (size_t low = start, high = last; low < high; low++, high--) {
            sort_copy(held, base + low * size, size);
            sort_copy(base + low * size, base + high * size, size);
            sort_copy(base + high * size, held, size);
        }
    } else {
        while (last + 1 < end && !sort_less(base + (last + 1) * size, base + last * size, kind)) last++;
    }
    return last - start + 1;
}
/* Extend the ascending run [start, sorted) to [start, end) by stable
   insertion: each element moves left only past elements greater than it. */
SORT_INLINE void sort_insertion(unsigned char *base, size_t start, size_t sorted, size_t end, sort_kind kind) {
    size_t size = sort_size(kind);
    unsigned char held[8];
    for (size_t i = sorted; i < end; i++) {
        if (!sort_less(base + i * size, base + (i - 1) * size, kind)) continue;
        sort_copy(held, base + i * size, size);
        size_t j = i;
        do {
            sort_copy(base + j * size, base + (j - 1) * size, size);
            j--;
        } while (j > start && sort_less(held, base + (j - 1) * size, kind));
        sort_copy(base + j * size, held, size);
    }
}
/* How many leading elements of the ascending `run` are not greater than
   `value`: the place a stable merge gives `value` when it comes from the right. */
SORT_INLINE size_t sort_upper_bound(const unsigned char *run, size_t count, const unsigned char *value, sort_kind kind) {
    size_t size = sort_size(kind), low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (sort_less(value, run + middle * size, kind)) high = middle;
        else low = middle + 1;
    }
    return low;
}
/* How many leading elements of the ascending `run` are less than `value`: the
   place a stable merge gives `value` when it comes from the left. */
SORT_INLINE size_t sort_lower_bound(const unsigned char *run, size_t count, const unsigned char *value, sort_kind kind) {
    size_t size = sort_size(kind), low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (sort_less(run + middle * size, value, kind)) low = middle + 1;
        else high = middle;
    }
    return low;
}
/* One comparison of two 8-byte elements held in registers. */
SORT_INLINE int sort_less_words(uint64_t left, uint64_t right, sort_kind kind) {
    unsigned char a[8], b[8];
    memcpy(a, &left, 8);
    memcpy(b, &right, 8);
    return sort_less(a, b, kind);
}
/* Merge the adjacent ascending runs [first, middle) and [middle, last). Only
   the stretch the two runs actually interleave over moves; the shorter side of
   it goes to `scratch`, which holds at least half the list.

   For 8-byte elements the bulk of the merge runs while both sides still hold
   two elements: the element after each side's head is loaded before the
   comparison that picks one, so advancing is a pair of selects rather than a
   load that has to wait for the comparison. The element loop finishes the
   last few elements and serves the narrower widths. */
SORT_INLINE void sort_merge(unsigned char *base, size_t first, size_t middle, size_t last, unsigned char *scratch, sort_kind kind) {
    size_t size = sort_size(kind);
    first += sort_upper_bound(base + first * size, middle - first, base + middle * size, kind);
    if (first == middle) return;
    last = middle + sort_lower_bound(base + middle * size, last - middle, base + (middle - 1) * size, kind);
    size_t left = middle - first, right = last - middle;
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
                int take_right = sort_less_words(y, x, kind);
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
            int take_right = sort_less(b, a, kind);
            sort_copy(out, take_right ? b : a, size);
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
                int take_left = sort_less_words(y, x, kind);
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
            int take_left = sort_less(b - size, a - size, kind);
            out -= size;
            sort_copy(out, take_left ? a - size : b - size, size);
            a -= take_left ? size : 0;
            b -= take_left ? 0 : size;
        }
        if (b > scratch) memcpy(out - (b - scratch), scratch, (size_t)(b - scratch));
    }
}
/* A run length in [SORT_MINRUN_LIMIT / 2, SORT_MINRUN_LIMIT] such that
   `count / minrun` is a power of two or just under one, as in listsort. */
static size_t sort_minrun(size_t count) {
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
static int sort_power(size_t start, size_t left, size_t right, size_t total) {
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
SORT_INLINE int sort_elements(unsigned char *base, size_t count, sort_kind kind) {
    size_t size = sort_size(kind), minrun = sort_minrun(count);
    unsigned char *scratch = NULL;
    if (count > minrun) {
        scratch = malloc(count / 2 * size);
        if (!scratch) return 0;
    }
    sort_run stack[SORT_STACK];
    size_t depth = 0, start = 0;
    for (;;) {
        /* Power 0 once the input is exhausted, which merges everything left. */
        int power = 0;
        size_t length = 0;
        if (start < count) {
            length = sort_natural_run(base, start, count, kind);
            if (length < minrun) {
                size_t end = count - start < minrun ? count : start + minrun;
                sort_insertion(base, start, start + length, end, kind);
                length = end - start;
            }
            if (depth) power = sort_power(stack[depth - 1].start, stack[depth - 1].length, length, count);
        }
        while (depth > 1 && (stack[depth - 2].power > power || depth == SORT_STACK)) {
            sort_run *left = &stack[depth - 2], *right = &stack[depth - 1];
            sort_merge(base, left->start, right->start, right->start + right->length, scratch, kind);
            left->length += right->length;
            depth--;
        }
        if (start >= count) break;
        if (depth) stack[depth - 1].power = power;
        stack[depth++] = (sort_run){ .start = start, .length = length, .power = 0 };
        start += length;
    }
    free(scratch);
    return 1;
}
static int sort_i64(unsigned char *base, size_t count) {
    return sort_elements(base, count, (sort_kind){ .kind = SORT_I64, .order = 0, .size = 8 });
}
static int sort_u64(unsigned char *base, size_t count) {
    return sort_elements(base, count, (sort_kind){ .kind = SORT_U64, .order = 1, .size = 8 });
}
static int sort_f64(unsigned char *base, size_t count) {
    return sort_elements(base, count, (sort_kind){ .kind = SORT_F64, .order = 2, .size = 8 });
}
static int sort_text(unsigned char *base, size_t count) {
    return sort_elements(base, count, (sort_kind){ .kind = SORT_TEXT, .order = 3, .size = 8 });
}
static int sort_generic(unsigned char *base, size_t count, unsigned order, size_t size) {
    return sort_elements(base, count, (sort_kind){ .kind = SORT_GENERIC, .order = order, .size = size });
}
int myl_native_list_sort(myl_native_list *list, unsigned order) {
    if (order > 3) return 0;
    if (list->length < 2) return 1;
    size_t size = list->element->size;
    if (size != 1 && size != 2 && size != 4 && size != 8) return 0;
    if ((order == 2 || order == 3) && size != 8) return 0;
    if (list->length > SIZE_MAX / size) return 0;
    unsigned char *base = list->storage;
    if (order == 2) return sort_f64(base, list->length);
    if (order == 3) return sort_text(base, list->length);
    if (size == 8) return order == 0 ? sort_i64(base, list->length) : sort_u64(base, list->length);
    return sort_generic(base, list->length, order, size);
}
myl_native_list *myl_native_list_copy(myl_native_heap *heap, const myl_native_list *input) {
    const myl_native_list *rooted = input;
    myl_native_root root;
    myl_native_root_push(heap, &root, &rooted, &pointer_type);
    myl_native_list *result = myl_native_list_new(heap, input->element, input->length);
    if (result) {
        if (input->length) memcpy(result->storage, input->storage, input->length * input->element->size);
        result->length = input->length;
    }
    myl_native_root_pop(heap, &root);
    return result;
}
/* Resolve an omitted endpoint, then apply Python's clamp for the step's sign. */
int64_t myl_native_slice_start(int64_t length, int64_t start, int64_t step) {
    if (start == MYL_NATIVE_SLICE_FIRST) start = step > 0 ? 0 : length - 1;
    if (step > 0) {
        if (start < 0) { start += length; if (start < 0) return 0; }
        else if (start > length) return length;
        return start;
    }
    if (start < 0) { start += length; if (start < 0) return -1; }
    else if (start >= length) return length - 1;
    return start;
}
int64_t myl_native_slice_stop(int64_t length, int64_t stop, int64_t step) {
    if (stop == MYL_NATIVE_SLICE_LAST) stop = step > 0 ? length : -length - 1;
    if (step > 0) {
        if (stop < 0) { stop += length; if (stop < 0) return 0; }
        else if (stop > length) return length;
        return stop;
    }
    if (stop < 0) { stop += length; if (stop < 0) return -1; }
    else if (stop >= length) return length - 1;
    return stop;
}
/* Element count between two adjusted endpoints, rounded up to whole steps. */
uint64_t myl_native_slice_count(int64_t start, int64_t stop, int64_t step) {
    if (step > 0) return stop > start ? (uint64_t)((stop - start + step - 1) / step) : 0;
    return start > stop ? (uint64_t)((start - stop - step - 1) / (-step)) : 0;
}
myl_native_list *myl_native_list_slice_step(myl_native_heap *heap, myl_native_list *input, int64_t start, int64_t stop, int64_t step) {
    if (!step) return NULL;
    const int64_t length = (int64_t)input->length;
    const int64_t first = myl_native_slice_start(length, start, step);
    const int64_t last = myl_native_slice_stop(length, stop, step);
    const uint64_t count = myl_native_slice_count(first, last, step);
    myl_native_root root;
    myl_native_root_push(heap, &root, &input, &pointer_type);
    myl_native_list *result = myl_native_list_new(heap, input->element, count);
    if (result) {
        int64_t at = first;
        for (uint64_t i = 0; i < count; i++) {
            memcpy((unsigned char *)result->storage + i * input->element->size,
                   (const unsigned char *)input->storage + (size_t)at * input->element->size, input->element->size);
            at += step;
        }
        result->length = count;
    }
    myl_native_root_pop(heap, &root);
    return result;
}
