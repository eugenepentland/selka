#include "native_collections.h"
#include "native_equal.h"
#include "native_text.h"
#include "native_rc_collections.h"
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
/* The header's one reference, as the collector's flat plan (GC-SCAN-PLAN-2). */
static const myl_native_scan_entry list_scan[] = {
    { .offset = offsetof(myl_native_list, storage), .tag_offset = MYL_NATIVE_SCAN_ALWAYS }
};
static const myl_native_type list_type = {
    .size = sizeof(myl_native_list), .alignment = _Alignof(myl_native_list),
    .kind = MYL_NATIVE_RECORD, .fields = list_fields, .field_count = 1,
    .scan = list_scan, .scan_count = 1
};
static myl_native_list *rc_list_new(myl_native_heap *, const myl_native_type *, size_t, unsigned, int);
static myl_native_list *rc_list_clone(myl_native_heap *, const myl_native_list *, const myl_native_type *, unsigned);
myl_native_list *myl_native_list_new(myl_native_heap *heap, const myl_native_type *element, size_t capacity) {
    if (!element) return NULL;
    if (myl_rc_enabled(heap)) return rc_list_new(heap,element,capacity,heap->region_depth,0);
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
    if (myl_rc_enabled(heap)) return myl_rc_list_append(heap,list,value);
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
    if (myl_rc_enabled(heap)) return myl_rc_list_insert(heap,list,index,value);
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
enum { KEY_SIGNED, KEY_UNSIGNED, KEY_FLOAT, KEY_TEXT };
typedef struct { unsigned count; unsigned char kind[8], size[8], offset[8]; } key_shape;
static int key_shape_decode(uint64_t shape, uint64_t offsets, size_t stride, key_shape *out) {
    static const unsigned char widths[4] = { 8, 4, 2, 1 };
    out->count = (unsigned)(shape & 15);
    if (out->count == 0 || out->count > 8) return 0;
    for (unsigned i = 0; i < out->count; i++) {
        unsigned field = (unsigned)(shape >> (4 + 4 * i)) & 15;
        out->kind[i] = (unsigned char)(field & 3);
        out->size[i] = widths[field >> 2];
        out->offset[i] = (unsigned char)(offsets >> (8 * i));
        if ((out->kind[i] == KEY_FLOAT || out->kind[i] == KEY_TEXT) && out->size[i] != 8) return 0;
        if ((size_t)out->offset[i] + out->size[i] > stride) return 0;
    }
    return 1;
}
/* One numeric key field as a word whose unsigned order is the key order. */
static inline uint64_t key_word(const unsigned char *at, unsigned kind, unsigned size) {
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
static inline int key_field_compare(const unsigned char *left, const unsigned char *right, const key_shape *shape, unsigned field) {
    const unsigned char *a = left + shape->offset[field], *b = right + shape->offset[field];
    if (shape->kind[field] == KEY_TEXT) {
        myl_native_text *x, *y;
        memcpy(&x, a, sizeof x);
        memcpy(&y, b, sizeof y);
        int order = myl_native_text_compare(x, y);
        return order < 0 ? -1 : order > 0;
    }
    uint64_t x = key_word(a, shape->kind[field], shape->size[field]);
    uint64_t y = key_word(b, shape->kind[field], shape->size[field]);
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
static void keyed_permute(myl_native_list *values, uint64_t *wide, size_t count, unsigned char *held) {
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
        copy_element(held, base + i * size, size);
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
                copy_element(base + j * size, held, size);
                break;
            }
            if (ahead != i) {
                ahead = count <= UINT32_MAX ? order[ahead] : (size_t)wide[ahead];
                __builtin_prefetch(base + ahead * size);
            }
            copy_element(base + j * size, base + k * size, size);
            j = k;
        }
    }
}
/* Where the ordered elements go: back into `source` itself along the
   permutation's cycles (an in-place sort, through `held`), or gathered in
   order from `source` into the empty list `values` (a sorted copy). */
typedef struct { myl_native_list *values; const myl_native_list *source; unsigned char *held; } keyed_target;
static void keyed_place(const keyed_target *target, uint64_t *order, size_t count) {
    if (target->values == target->source) {
        keyed_permute(target->values, order, count, target->held);
        return;
    }
    size_t size = target->source->element->size;
    unsigned char *out = target->values->storage;
    const unsigned char *in = target->source->storage;
    for (size_t i = 0; i < count; i++) copy_element(out + i * size, in + (size_t)order[i] * size, size);
    target->values->length = count;
    target->values->generation++;
}
/* Move every element to the slot `dest` names for it: the element at `i`
   goes to `dest[i]`. In place this follows each cycle once, carrying one
   element in `held` and marking each handled position `dest[p] = p`, with the
   same narrowed table and lookahead prefetch as keyed_permute; for a copy it
   scatters the elements into the empty target. */
static void keyed_place_dest(const keyed_target *target, uint64_t *wide, size_t count) {
    size_t size = target->source->element->size;
    if (target->values != target->source) {
        unsigned char *out = target->values->storage;
        const unsigned char *in = target->source->storage;
        for (size_t i = 0; i < count; i++) copy_element(out + (size_t)wide[i] * size, in + i * size, size);
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
        copy_element(held, base + i * size, size);
        size_t p = i, ahead = i;
        for (int step = 0; step < KEYED_LOOKAHEAD && (step == 0 || ahead != i); step++) {
            ahead = dest[ahead];
            __builtin_prefetch(base + ahead * size);
        }
        for (;;) {
            size_t d = dest[p];
            dest[p] = (uint32_t)p;
            if (d == i) {
                copy_element(base + i * size, held, size);
                break;
            }
            if (ahead != i) {
                ahead = dest[ahead];
                __builtin_prefetch(base + ahead * size);
            }
            copy_element(swap, base + d * size, size);
            copy_element(base + d * size, held, size);
            copy_element(held, swap, size);
            p = d;
        }
    }
}
/* A single numeric key whose words span fewer values than there are
   elements: a stable counting sort. One pass counts each key, a prefix sum
   turns the counts into first slots, and a second pass gives each element,
   in input order, the next slot of its key — so equal keys keep input order
   without any comparison. */
static int keyed_count(const keyed_target *target, myl_native_list *keys, const key_shape *shape, uint64_t flip, uint64_t low, uint64_t span) {
    size_t count = target->source->length, stride = keys->element->size;
    const unsigned char *rows = keys->storage;
    unsigned kind = shape->kind[0], size = shape->size[0], offset = shape->offset[0];
    uint32_t *slots = calloc((size_t)span + 1, sizeof *slots);
    if (!slots) return 0;
    for (size_t i = 0; i < count; i++) slots[(key_word(rows + i * stride + offset, kind, size) ^ flip) - low]++;
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
    for (size_t i = 0; i < count; i++) dest[i] = slots[(key_word(rows + i * stride + offset, kind, size) ^ flip) - low]++;
    free(slots);
    keyed_place_dest(target, dest, count);
    if (!own) free(dest);
    return 1;
}
typedef struct { uint64_t word; uint64_t position; } keyed_entry;
typedef struct { const unsigned char *keys; size_t stride; const key_shape *shape; unsigned reverse; } keyed_order;
/* Whether entry `a` goes strictly before entry `b`. A single text key is
   carried in the entry itself; any other key is read from its row. */
static inline int keyed_less(const keyed_entry *a, const keyed_entry *b, const keyed_order *by) {
    const keyed_entry *x = by->reverse ? b : a, *y = by->reverse ? a : b;
    if (by->shape->count == 1 && by->shape->kind[0] == KEY_TEXT) {
        myl_native_text *p, *q;
        memcpy(&p, &x->word, sizeof p);
        memcpy(&q, &y->word, sizeof q);
        return myl_native_text_compare(p, q) < 0;
    }
    const unsigned char *left = by->keys + (size_t)x->position * by->stride;
    const unsigned char *right = by->keys + (size_t)y->position * by->stride;
    for (unsigned field = 0; field < by->shape->count; field++) {
        int order = key_field_compare(left, right, by->shape, field);
        if (order) return order < 0;
    }
    return 0;
}
/* Stable bottom-up merge of entries: insertion-sorted blocks of 16, then
   passes that merge adjacent blocks between `entries` and `spare`, taking
   the left entry on a tie. Returns the array holding the result. */
static keyed_entry *keyed_merge_sort(keyed_entry *entries, keyed_entry *spare, size_t count, const keyed_order *by) {
    for (size_t start = 0; start < count; start += 16) {
        size_t end = count - start < 16 ? count : start + 16;
        for (size_t i = start + 1; i < end; i++) {
            keyed_entry held = entries[i];
            size_t j = i;
            while (j > start && keyed_less(&held, &entries[j - 1], by)) {
                entries[j] = entries[j - 1];
                j--;
            }
            entries[j] = held;
        }
    }
    keyed_entry *from = entries, *to = spare;
    for (size_t width = 16; width < count; width *= 2) {
        for (size_t start = 0; start < count; start += 2 * width) {
            size_t middle = count - start < width ? count : start + width;
            size_t end = count - middle < width ? count : middle + width;
            size_t a = start, b = middle, out = start;
            while (a < middle && b < end) to[out++] = keyed_less(&from[b], &from[a], by) ? from[b++] : from[a++];
            while (a < middle) to[out++] = from[a++];
            while (b < end) to[out++] = from[b++];
        }
        keyed_entry *swap = from;
        from = to;
        to = swap;
    }
    return from;
}
static int keyed_sort_entries(const keyed_target *target, const myl_native_list *keys, const key_shape *shape, unsigned reverse) {
    size_t count = target->source->length, stride = keys->element->size;
    if (count > SIZE_MAX / (2 * sizeof(keyed_entry))) return 0;
    keyed_entry *entries = malloc(2 * count * sizeof *entries);
    if (!entries) return 0;
    const unsigned char *rows = keys->storage;
    for (size_t i = 0; i < count; i++) {
        entries[i].position = i;
        entries[i].word = 0;
        if (shape->count == 1 && shape->kind[0] == KEY_TEXT) memcpy(&entries[i].word, rows + i * stride + shape->offset[0], 8);
    }
    keyed_order by = { .keys = rows, .stride = stride, .shape = shape, .reverse = reverse };
    keyed_entry *sorted = keyed_merge_sort(entries, entries + count, count, &by);
    uint64_t *order = (uint64_t *)entries;
    /* Entry `i` is 16 bytes and position `i` is 8, so compacting forward
       never overwrites an entry not yet read, whichever half holds them. */
    for (size_t i = 0; i < count; i++) order[i] = sorted[i].position;
    keyed_place(target, order, count);
    free(entries);
    return 1;
}
/* One numeric key: pack `(word - low) << bits | position` into one integer
   per element when that fits, else sort by the low 32 bits of the word and
   then, stably, by the high 32 bits. */
static int keyed_sort_words(const keyed_target *target, myl_native_list *keys, const key_shape *shape, unsigned reverse) {
    size_t count = target->source->length, stride = keys->element->size;
    const unsigned char *rows = keys->storage;
    unsigned kind = shape->kind[0], size = shape->size[0], offset = shape->offset[0];
    uint64_t flip = reverse ? UINT64_MAX : 0, low = UINT64_MAX, high = 0;
    for (size_t i = 0; i < count; i++) {
        uint64_t word = key_word(rows + i * stride + offset, kind, size) ^ flip;
        low = word < low ? word : low;
        high = word > high ? word : high;
    }
    if (count <= UINT32_MAX && high - low < count) return keyed_count(target, keys, shape, flip, low, high - low);
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
        for (size_t i = 0; i < count; i++) words[i] = ((key_word(rows + i * stride + offset, kind, size) ^ flip) - low) << bits | i;
        if (!sort_u64((unsigned char *)words, count)) {
            if (!own) free(words);
            return 0;
        }
        for (size_t i = 0; i < count; i++) words[i] &= mask;
        keyed_place(target, words, count);
        if (!own) free(words);
        return 1;
    }
    if (bits > 32) return keyed_sort_entries(target, keys, shape, reverse);
    uint64_t *by_low = malloc(count * 8), *by_high = malloc(count * 8);
    if (!by_low || !by_high) {
        free(by_low);
        free(by_high);
        return 0;
    }
    for (size_t i = 0; i < count; i++) by_low[i] = ((key_word(rows + i * stride + offset, kind, size) ^ flip) & UINT32_MAX) << bits | i;
    int sorted = sort_u64((unsigned char *)by_low, count);
    for (size_t rank = 0; sorted && rank < count; rank++) {
        uint64_t word = key_word(rows + (by_low[rank] & mask) * stride + offset, kind, size) ^ flip;
        by_high[rank] = (word >> 32) << bits | rank;
    }
    if (sorted) sorted = sort_u64((unsigned char *)by_high, count);
    if (sorted) {
        for (size_t i = 0; i < count; i++) by_high[i] = by_low[by_high[i] & mask] & mask;
        keyed_place(target, by_high, count);
    }
    free(by_low);
    free(by_high);
    return sorted;
}
int myl_native_list_sort_keyed(myl_native_list *values, myl_native_list *source, myl_native_list *keys, uint64_t shape, uint64_t offsets, uint64_t reverse) {
    key_shape decoded;
    if (!source || !keys || keys->length != source->length) return 0;
    size_t count = source->length, size = source->element->size;
    /* A sorted copy gathers into an empty list with room for every element. */
    if (values != source && (values->length != 0 || values->capacity < count || values->element->size != size)) return 0;
    if (!key_shape_decode(shape, offsets, keys->element->size, &decoded)) return 0;
    if (count < 2) {
        uint64_t first = 0;
        if (values != source && count) keyed_place(&(keyed_target){ .values = values, .source = source }, &first, 1);
        return 1;
    }
    /* Two element-sized temporaries: the one carried along a cycle, and the
       one it is exchanged through. */
    unsigned char inline_held[128];
    unsigned char *held = values != source || 2 * size <= sizeof inline_held ? inline_held : malloc(2 * size);
    if (!held) return 0;
    keyed_target target = { .values = values, .source = source, .held = held };
    int done = decoded.count == 1 && decoded.kind[0] != KEY_TEXT
        ? keyed_sort_words(&target, keys, &decoded, reverse != 0)
        : keyed_sort_entries(&target, keys, &decoded, reverse != 0);
    if (held != inline_held) free(held);
    return done;
}
myl_native_list *myl_native_list_copy(myl_native_heap *heap, const myl_native_list *input) {
    if (myl_rc_enabled(heap)) return rc_list_clone(heap,input,input->element,heap->region_depth);
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
int myl_native_list_header(const void *payload) {
    return payload && ((const myl_native_object *)payload - 1)->element == &list_type;
}
myl_native_list *myl_native_list_clone_at(myl_native_heap *heap, const myl_native_list *input, const myl_native_type *element, unsigned region) {
    if (myl_rc_enabled(heap)) return rc_list_clone(heap,input,element,region);
    const myl_native_list *rooted = input;
    myl_native_root source_root, clone_root;
    myl_native_root_push(heap, &source_root, &rooted, &pointer_type);
    myl_native_list *clone = myl_native_heap_alloc_at(heap, &list_type, 1, region);
    if (clone) {
        myl_native_root_push(heap, &clone_root, &clone, &pointer_type);
        size_t capacity = rooted->capacity > rooted->length ? rooted->capacity : rooted->length;
        clone->element = element;
        if (capacity) {
            void *storage = myl_native_heap_alloc_at(heap, element, capacity, region);
            if (storage && rooted->length) memcpy(storage, rooted->storage, rooted->length * rooted->element->size);
            clone->storage = storage;
        }
        myl_native_root_pop(heap, &clone_root);
        if (capacity && !clone->storage) clone = NULL;
        else {
            clone->length = rooted->length;
            clone->capacity = capacity;
        }
    }
    myl_native_root_pop(heap, &source_root);
    return clone;
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
            const void *source=(const unsigned char *)input->storage+(size_t)at*input->element->size;
            if (myl_rc_enabled(heap)) {
                if (!myl_rc_list_append(heap,result,source)) {
                    myl_rc_owner_release(heap,result);
                    result=NULL;
                    break;
                }
            } else memcpy((unsigned char *)result->storage+i*input->element->size,source,input->element->size);
            at += step;
        }
        if (result) result->length = count;
    }
    myl_native_root_pop(heap, &root);
    return result;
}
/* The list header owns logical elements. Its backing owns only raw bytes, so
 * a held retired block remains valid without duplicating the elements' edges. */
static void rc_list_edges(myl_native_heap *heap, void *payload, size_t count) {
    (void)count;
    myl_native_list *list=payload;
    if (list->length) {
        const myl_rc_descriptor *element=myl_rc_descriptor_find(heap,list->element);
        if (!element) abort();
        myl_rc_edges_release(heap,element->shape,list->storage,list->length);
    }
    myl_rc_edge_release(heap,list->storage);
}
static void rc_storage_edges(myl_native_heap *heap, void *payload, size_t count) {
    (void)count;
    myl_rc_edge_release(heap,((myl_native_list *)payload)->storage);
}
static const myl_native_type rc_storage_type={
    .size=sizeof(myl_native_list),.alignment=_Alignof(myl_native_list),.kind=MYL_NATIVE_PLAIN
};
static const myl_rc_shape rc_list_shape={.size=sizeof(myl_native_list),.kind=MYL_RC_SHAPE_NONE};
static myl_rc_status rc_list_clone_adapter(myl_native_heap *heap, const void *payload, unsigned region, void **out) {
    const myl_native_list *input=payload;
    *out=rc_list_clone(heap,input,input->element,region);
    return myl_rc_native_result(heap,*out);
}
static const myl_rc_descriptor rc_list_descriptors[]={
    {.type=&list_type,.shape=&rc_list_shape,.edges=rc_list_edges,.clone=rc_list_clone_adapter},
    {.type=&rc_storage_type,.shape=&rc_list_shape,.edges=rc_storage_edges}
};
static const myl_rc_module rc_list_module={
    .abi=MYL_RC_ABI_VERSION,.descriptors=rc_list_descriptors,.descriptor_count=2
};
static myl_native_list *rc_list_new(myl_native_heap *heap, const myl_native_type *element, size_t capacity, unsigned region, int raw) {
    if (!raw && !myl_rc_native_shape(heap,element)) return NULL;
    myl_rc_status status=myl_rc_module_register(heap,&rc_list_module);
    if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); return NULL; }
    myl_rc_alloc_request request={raw?&rc_storage_type:&list_type,1,region};
    myl_native_list *list=NULL;
    status=myl_rc_new(heap,&request,(void **)&list);
    if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); return NULL; }
    list->element=element;
    if (capacity) list->storage=myl_rc_native_storage(heap,element,capacity,region);
    if (capacity && !list->storage) { myl_rc_owner_release(heap,list); return NULL; }
    list->capacity=capacity;
    return list;
}
myl_native_list *myl_rc_list_storage_new(myl_native_heap *heap, const myl_native_type *element, size_t capacity, unsigned region) {
    return rc_list_new(heap,element,capacity,region,1);
}
int myl_rc_list_storage_reserve(myl_native_heap *heap, myl_native_list *list, size_t needed) {
    if (needed<=list->capacity) return 1;
    size_t capacity=list->capacity<4?4:list->capacity;
    while (capacity<needed) {
        if (capacity>SIZE_MAX/2) return 0;
        capacity*=2;
    }
    if (list->element->size && capacity>SIZE_MAX/list->element->size) return 0;
    void *old=list->storage;
    void *storage=myl_rc_storage_extend(heap,old,capacity*list->element->size);
    if (!storage) {
        storage=myl_rc_native_storage(heap,list->element,capacity,myl_native_header_region(list));
        if (!storage) return 0;
        if (list->length) memcpy(storage,old,list->length*list->element->size);
        list->storage=storage;
        myl_rc_owner_release(heap,old);
    } else list->storage=storage;
    list->capacity=capacity;
    return 1;
}
static int rc_list_insert_at(myl_native_heap *heap, myl_native_list *list, size_t at, const void *value) {
    if (list->generation==UINT64_MAX || list->length==SIZE_MAX) return 0;
    size_t size=list->element->size;
    unsigned char local[128];
    void *staged=size<=sizeof local?local:myl_rc_storage_bytes(heap,size,0);
    if (!staged) return 0;
    unsigned region=myl_native_header_region(list);
    int ok=myl_rc_native_copy(heap,list->element,staged,value,region);
    if (ok && !myl_rc_list_storage_reserve(heap,list,list->length+1)) {
        myl_rc_native_drop(heap,list->element,staged);
        ok=0;
    }
    if (ok) {
        unsigned char *storage=list->storage;
        if (at<list->length) memmove(storage+(at+1)*size,storage+at*size,(list->length-at)*size);
        if (size) memcpy(storage+at*size,staged,size);
        list->length++;
        list->generation++;
    }
    if (staged!=local) myl_rc_owner_release(heap,staged);
    return ok;
}
int myl_rc_list_append(myl_native_heap *heap, myl_native_list *list, const void *value) {
    return rc_list_insert_at(heap,list,list->length,value);
}
int myl_rc_list_insert(myl_native_heap *heap, myl_native_list *list, int64_t index, const void *value) {
    size_t at;
    if (index<0) {
        uint64_t distance=(uint64_t)(-(index+1))+1;
        at=distance>list->length?0:list->length-(size_t)distance;
    } else at=(uint64_t)index>list->length?list->length:(size_t)index;
    return rc_list_insert_at(heap,list,at,value);
}
int myl_rc_list_set(myl_native_heap *heap, myl_native_list *list, size_t index, const void *value) {
    if (index>=list->length) return 0;
    return myl_rc_native_replace(heap,list->element,(unsigned char *)list->storage+index*list->element->size,value,myl_native_header_region(list));
}
static int rc_list_remove_at(myl_native_heap *heap, myl_native_list *list, size_t at, void *output) {
    if (at>=list->length || list->generation==UINT64_MAX) return 0;
    size_t size=list->element->size;
    unsigned char *slot=(unsigned char *)list->storage+at*size;
    if (output) {
        if (!myl_rc_native_take(heap,list->element,output,slot,heap->region_depth)) return -1;
    } else {
        const myl_rc_descriptor *descriptor=myl_rc_descriptor_find(heap,list->element);
        if (!descriptor) abort();
        myl_rc_edges_release(heap,descriptor->shape,slot,1);
    }
    size_t moved=list->length-at-1;
    if (moved) memmove(slot,slot+size,moved*size);
    memset((unsigned char *)list->storage+(list->length-1)*size,0,size);
    list->length--;
    list->generation++;
    myl_rc_drain(heap);
    return 1;
}
int myl_rc_list_pop(myl_native_heap *heap, myl_native_list *list, void *output) {
    return list->length?rc_list_remove_at(heap,list,list->length-1,output):0;
}
int myl_rc_list_pop_at(myl_native_heap *heap, myl_native_list *list, int64_t index, void *output) {
    size_t at;
    if (index<0) {
        uint64_t distance=(uint64_t)(-(index+1))+1;
        if (distance>list->length) return 0;
        at=list->length-(size_t)distance;
    } else at=(size_t)index;
    return rc_list_remove_at(heap,list,at,output);
}
int myl_rc_list_clear(myl_native_heap *heap, myl_native_list *list) {
    if (!list->length) return 1;
    if (list->generation==UINT64_MAX) return 0;
    const myl_rc_descriptor *descriptor=myl_rc_descriptor_find(heap,list->element);
    if (!descriptor) abort();
    size_t length=list->length;
    list->length=0;
    list->generation++;
    myl_rc_edges_release(heap,descriptor->shape,list->storage,length);
    memset(list->storage,0,length*list->element->size);
    myl_rc_drain(heap);
    return 1;
}
int myl_rc_list_remove(myl_native_heap *heap, myl_native_list *list, const void *value) {
    int64_t at=0;
    int found=myl_native_list_index(list,value,&at);
    return found==1?rc_list_remove_at(heap,list,(size_t)at,NULL):found;
}
static myl_native_list *rc_list_clone(myl_native_heap *heap, const myl_native_list *input, const myl_native_type *element, unsigned region) {
    size_t capacity=input->capacity>input->length?input->capacity:input->length;
    myl_native_list *clone=rc_list_new(heap,element,capacity,region,0);
    if (!clone) return NULL;
    for (size_t i=0;i<input->length;i++) {
        if (!myl_rc_list_append(heap,clone,(const unsigned char *)input->storage+i*element->size)) {
            myl_rc_owner_release(heap,clone);
            return NULL;
        }
    }
    clone->generation=0;
    return clone;
}
int myl_rc_list_sort_keyed(myl_native_heap *heap, const myl_rc_sort_request *request) {
    myl_native_list *source=request->source;
    myl_native_list *temporary=NULL;
    if (request->values!=source) {
        temporary=rc_list_clone(heap,source,source->element,myl_native_header_region(request->values));
        if (!temporary) return 0;
        source=temporary;
    }
    int ok=myl_native_list_sort_keyed(source,source,request->keys,request->shape,request->offsets,request->reverse);
    if (ok && temporary) {
        if (request->values->length || request->values->capacity<temporary->length) ok=0;
        else {
            memcpy(request->values->storage,temporary->storage,temporary->length*temporary->element->size);
            request->values->length=temporary->length;
            temporary->length=0;
        }
    }
    if (temporary) myl_rc_owner_release(heap,temporary);
    return ok;
}
