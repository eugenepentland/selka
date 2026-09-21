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
static int compare_float(const void *left, const void *right) {
    double a, b;
    memcpy(&a, left, 8);
    memcpy(&b, right, 8);
    if (isnan(a)) return isnan(b) ? 0 : 1;
    if (isnan(b)) return -1;
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}
static int compare_text(const void *left, const void *right) {
    myl_native_text *a, *b;
    memcpy(&a,left,sizeof a);
    memcpy(&b,right,sizeof b);
    return myl_native_text_compare(a,b);
}
static int compare_element(const void *left, const void *right, size_t size, unsigned order) {
    if (order==0) return compare_signed(left,right,size);
    if (order==1) return compare_unsigned(left,right,size);
    if (order==2) return compare_float(left,right);
    return compare_text(left,right);
}
int myl_native_list_sort(myl_native_list *list, unsigned order) {
    if (order > 3) return 0;
    if (list->length < 2) return 1;
    size_t size = list->element->size;
    if (!size || list->length>SIZE_MAX/size) return 0;
    size_t bytes=list->length*size;
    unsigned char *buffer=malloc(bytes);
    if (!buffer) return 0;
    unsigned char *storage=list->storage, *source=storage, *target=buffer;
    size_t width=1;
    while (width<list->length) {
        for (size_t start=0;start<list->length;) {
            size_t middle=list->length-start<width?list->length:start+width;
            size_t remaining=list->length-middle;
            size_t end=remaining<width?list->length:middle+width;
            size_t left=start, right=middle, out=start;
            while (left<middle && right<end) {
                size_t take=compare_element(source+left*size,source+right*size,size,order)<=0?left++:right++;
                copy_element(target+out*size,source+take*size,size);
                out++;
            }
            while (left<middle) copy_element(target+out++*size,source+left++*size,size);
            while (right<end) copy_element(target+out++*size,source+right++*size,size);
            start=end;
        }
        unsigned char *swap=source; source=target; target=swap;
        width=width>list->length/2?list->length:width*2;
    }
    if (source!=storage) memcpy(storage,source,bytes);
    free(buffer);
    return 1;
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
