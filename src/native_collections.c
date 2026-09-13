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
        void *storage = myl_native_heap_alloc(heap, list->element, capacity);
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
