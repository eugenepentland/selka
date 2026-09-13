#include "native_heap.h"
#include <stdlib.h>
#include <string.h>
#include <stdalign.h>
struct myl_native_object {
    struct myl_native_object *next, *pending;
    const myl_native_type *element;
    size_t count, bytes;
    unsigned marked;
    max_align_t payload_alignment;
};
static void trace(myl_native_heap *, const myl_native_type *, const void *);
static void mark(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    if (object->marked) return;
    object->marked = 1;
    object->pending = heap->pending;
    heap->pending = object;
}
static void trace(myl_native_heap *heap, const myl_native_type *type, const void *address) {
    const unsigned char *bytes = address;
    if (type->kind == MYL_NATIVE_POINTER || type->kind == MYL_NATIVE_OWNED_BUFFER || type->kind == MYL_NATIVE_OWNED_POOL) {
        void *pointer;
        memcpy(&pointer, bytes, sizeof(pointer));
        mark(heap, pointer);
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; ++i)
            trace(heap, type->fields[0].type, bytes + i * type->stride);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, bytes, sizeof(tag));
        for (size_t i = 0; i < type->field_count; ++i) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || tag == field->tag)
                trace(heap, field->type, bytes + field->offset);
        }
    }
}
void myl_native_heap_init(myl_native_heap *heap, size_t limit) {
    memset(heap, 0, sizeof(*heap));
    heap->limit = limit;
    heap->next_pool_identity = 1;
    heap->next_collection = 65536;
}
void myl_native_root_push(myl_native_heap *heap, myl_native_root *root,
                          void *address, const myl_native_type *type) {
    root->previous = heap->roots;
    root->address = address;
    root->type = type;
    heap->roots = root;
}
int myl_native_root_pop(myl_native_heap *heap, myl_native_root *root) {
    if (heap->roots != root) return 0;
    heap->roots = root->previous;
    return 1;
}
void myl_native_heap_collect(myl_native_heap *heap) {
    heap->collections++;
    for (myl_native_root *root = heap->roots; root; root = root->previous)
        trace(heap, root->type, root->address);
    while (heap->pending) {
        myl_native_object *object = heap->pending;
        heap->pending = object->pending;
        const unsigned char *payload = (const unsigned char *)(object + 1);
        if (object->element->kind != MYL_NATIVE_PLAIN)
            for (size_t i = 0; i < object->count; ++i)
                trace(heap, object->element, payload + i * object->element->size);
    }
    myl_native_object **link = &heap->objects;
    while (*link) {
        myl_native_object *object = *link;
        if (object->marked) {
            object->marked = 0;
            link = &object->next;
        } else {
            *link = object->next;
            heap->bytes -= object->bytes;
            heap->objects_live--;
            free(object);
        }
    }
    heap->next_collection = heap->bytes > (SIZE_MAX-65536)/2 ? SIZE_MAX : heap->bytes*2+65536;
}
void *myl_native_heap_alloc(myl_native_heap *heap, const myl_native_type *element, size_t count) {
    if (!element || !element->alignment || element->alignment > alignof(max_align_t)) return NULL;
    if ((element->alignment & (element->alignment - 1)) || element->size % element->alignment) return NULL;
    if (element->size && count > (SIZE_MAX - sizeof(myl_native_object)) / element->size) return NULL;
    size_t bytes = sizeof(myl_native_object) + count * element->size;
    if (heap->stress || heap->bytes > heap->limit || bytes > heap->limit - heap->bytes || heap->bytes >= heap->next_collection || bytes > heap->next_collection - heap->bytes) myl_native_heap_collect(heap);
    if (heap->bytes > heap->limit || bytes > heap->limit - heap->bytes) return NULL;
    myl_native_object *object = calloc(1, bytes);
    if (!object) return NULL;
    object->next = heap->objects;
    object->element = element;
    object->count = count;
    object->bytes = bytes;
    heap->objects = object;
    heap->bytes += bytes;
    heap->objects_live++;
    heap->allocations++;
    return object + 1;
}
void myl_native_heap_destroy(myl_native_heap *heap) {
    myl_native_object *object = heap->objects;
    while (object) {
        myl_native_object *next = object->next;
        free(object);
        object = next;
    }
    memset(heap, 0, sizeof(*heap));
}

void myl_native_heap_release(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    myl_native_object **link = &heap->objects;
    while (*link && *link != object) link = &(*link)->next;
    if (!*link) return;
    *link = object->next;
    heap->bytes -= object->bytes;
    heap->objects_live--;
    free(object);
}

/* Release every external resource reachable from a value, nesting through
   ordinary records, arrays and variants. Managed collections are traced by the
   collector instead, so they are not owners here. */
static void myl_native_schedule(myl_native_drop_link **work, const myl_native_type *type, void *value) {
    if (type->kind == MYL_NATIVE_RESOURCE) {
        void *owner = NULL;
        memcpy(&owner, value, sizeof owner);
        memset(value, 0, sizeof owner);
        if (!owner) return;
        myl_native_drop_link *link = &((myl_native_resource *)owner)->work;
        *link = (myl_native_drop_link){.next = *work, .owner = owner, .kind = type->kind};
        *work = link;
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; i++)
            myl_native_schedule(work, type->fields[0].type, (unsigned char *)value + i * type->stride);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, value, sizeof tag);
        for (size_t i = 0; i < type->field_count; i++) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || field->tag == tag)
                myl_native_schedule(work, field->type, (unsigned char *)value + field->offset);
        }
    }
}

void myl_native_owned_drop(myl_native_heap *heap, const myl_native_type *type, void *value) {
    (void)heap;
    myl_native_drop_link *work = NULL;
    myl_native_schedule(&work, type, value);
    while (work) {
        myl_native_resource *owner = work->owner;
        work = work->next;
        owner->drop(owner);
    }
}
