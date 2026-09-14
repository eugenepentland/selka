#include "native_collections.h"
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
int myl_native_list_append(myl_native_heap *heap, myl_native_list *list, const void *value) {
    if (list->generation == UINT64_MAX) return 0;
    myl_native_root owner_root, value_root;
    myl_native_root_push(heap, &owner_root, &list, &pointer_type);
    myl_native_root_push(heap, &value_root, (void *)value, list->element);
    if (list->length == list->capacity) {
        size_t capacity = list->capacity < 4 ? 4 : list->capacity;
        if (list->capacity >= 4) {
            if (capacity > SIZE_MAX / 2) goto failure;
            capacity *= 2;
        }
        /* Grown backing joins the list's own arena, so an append performed inside
           a younger arena never leaves an older list with storage that is about
           to be bulk released. */
        void *storage = myl_native_heap_alloc_at(heap, list->element, capacity, myl_native_object_region(list));
        if (!storage) goto failure;
        if (list->length) memcpy(storage, list->storage, list->length * list->element->size);
        /* value may point into old backing; copy before unlinking that backing. */
        memcpy((unsigned char *)storage + list->length * list->element->size, value, list->element->size);
        list->storage = storage;
        list->capacity = capacity;
    } else {
        memcpy((unsigned char *)list->storage + list->length * list->element->size, value, list->element->size);
    }
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
int myl_native_list_get(const myl_native_list *list, size_t index, void *output) {
    if (index >= list->length) return 0;
    memmove(output, (const unsigned char *)list->storage + index * list->element->size, list->element->size);
    return 1;
}
int myl_native_list_set(myl_native_list *list, size_t index, const void *value) {
    if (index >= list->length) return 0;
    memmove((unsigned char *)list->storage + index * list->element->size, value, list->element->size);
    return 1;
}
int myl_native_list_pop(myl_native_list *list, void *output) {
    if (!list->length || list->generation == UINT64_MAX) return 0;
    list->length--;
    unsigned char *slot = (unsigned char *)list->storage + list->length * list->element->size;
    memmove(output, slot, list->element->size);
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
/* Resolve an omitted endpoint, then apply Python's clamp for the step's sign. */
static int64_t slice_start(int64_t length, int64_t start, int64_t step) {
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
static int64_t slice_stop(int64_t length, int64_t stop, int64_t step) {
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
static uint64_t slice_count(int64_t start, int64_t stop, int64_t step) {
    if (step > 0) return stop > start ? (uint64_t)((stop - start + step - 1) / step) : 0;
    return start > stop ? (uint64_t)((start - stop - step - 1) / (-step)) : 0;
}
myl_native_list *myl_native_list_slice_step(myl_native_heap *heap, myl_native_list *input, int64_t start, int64_t stop, int64_t step) {
    if (!step) return NULL;
    const int64_t length = (int64_t)input->length;
    const int64_t first = slice_start(length, start, step);
    const int64_t last = slice_stop(length, stop, step);
    const uint64_t count = slice_count(first, last, step);
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
