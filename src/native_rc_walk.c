#include "native_rc_internal.h"
#include <string.h>

static void push(myl_native_heap *heap, const myl_rc_shape *shape, unsigned char *address) {
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
    myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth++];
    *frame = (myl_rc_frame){.shape = shape, .address = address};
}
/* Frames keep the next child/index, not an expanded list of array elements. */
enum { WALK_CLEAR, WALK_RELEASE, WALK_REGION };
static unsigned walk(myl_native_heap *heap, unsigned action) {
    unsigned region = 0;
    while (heap->rc->walk.depth) {
        myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
        const myl_rc_shape *shape = frame->shape;
        if (shape->kind == MYL_RC_SHAPE_POINTER) {
            void *payload;
            memcpy(&payload, frame->address, sizeof payload);
            if (action == WALK_REGION) {
                unsigned found = payload ? myl_native_header_region(payload) : 0;
                if (found > region) region = found;
            } else memset(frame->address, 0, sizeof payload);
            --heap->rc->walk.depth;
            if (action == WALK_RELEASE) myl_rc_edge_release(heap, payload);
        } else if (shape->kind == MYL_RC_SHAPE_ARRAY) {
            if (frame->cursor == shape->as.array.count) { --heap->rc->walk.depth; continue; }
            size_t index = frame->cursor++;
            push(heap, shape->as.array.element, frame->address + index * shape->as.array.stride);
        } else {
            myl_rc_invariant(shape->kind == MYL_RC_SHAPE_RECORD || shape->kind == MYL_RC_SHAPE_VARIANT);
            const myl_rc_field *fields = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.fields : shape->as.variant.fields;
            size_t count = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.count : shape->as.variant.count;
            if (frame->cursor == count) { --heap->rc->walk.depth; continue; }
            const myl_rc_field *field = &fields[frame->cursor++];
            if (shape->kind == MYL_RC_SHAPE_VARIANT) {
                uint32_t tag;
                memcpy(&tag, frame->address + shape->as.variant.tag_offset, sizeof tag);
                if (field->tag != tag) continue;
            }
            push(heap, field->shape, frame->address + field->offset);
        }
    }
    return region;
}
unsigned myl_rc_value_region(myl_native_heap *heap, const myl_rc_shape *source, const void *address) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, source);
    myl_rc_invariant(shape && (!shape->size || address));
    push(heap, shape, (unsigned char *)address);
    return walk(heap, WALK_REGION);
}
void myl_rc_edges_release(myl_native_heap *heap, const myl_rc_shape *source, void *address, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, source);
    myl_rc_invariant(shape != NULL);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(shape->size, count, &bytes));
    myl_rc_invariant(!bytes || address);
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    unsigned char *cursor = address;
    for (size_t i = 0; i < count; ++i) {
        push(heap, shape, cursor);
        walk(heap, WALK_RELEASE);
        cursor += shape->size;
    }
}
void myl_rc_drain(myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc);
    if (heap->rc->dead.active || heap->rc->walk.depth) return;
    heap->rc->dead.active = 1;
    while (heap->rc->dead.head) {
        myl_rc_object *object = heap->rc->dead.head;
        heap->rc->dead.head = (myl_rc_object *)object->owners;
        void *payload = object + 1;
        const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(heap, object->common.element);
        myl_rc_invariant(descriptor != NULL);
        size_t count = (size_t)((object->common.mark & MYL_NATIVE_OBJECT_COUNT_BITS) >> MYL_NATIVE_OBJECT_COUNT_SHIFT);
        /* A unique close hook can inspect its managed context. Run it while
         * child tokens are intact, with no descriptor frame leased. Nested
         * releases only enqueue. Reacquire metadata after a registering hook. */
        void (*finalize)(myl_native_heap *, void *) = descriptor->finalize;
        if (finalize) finalize(heap, payload);
        descriptor = myl_rc_descriptor_find(heap, object->common.element);
        myl_rc_invariant(descriptor && !heap->rc->walk.depth);
        if (descriptor->edges) descriptor->edges(heap, payload, count);
        else myl_rc_edges_release(heap, descriptor->shape, payload, count);
        myl_rc_invariant(!heap->rc->walk.depth);
        myl_rc_allocator_retire(heap, payload);
    }
    heap->rc->dead.active = 0;
}
void myl_rc_value_drop(myl_native_heap *heap, myl_rc_slot *slot) {
    myl_rc_invariant(slot && slot->shape && slot->address);
    myl_rc_edges_release(heap, slot->shape, slot->address, 1);
    memset(slot->address, 0, slot->shape->size);
    myl_rc_drain(heap);
}
void myl_rc_value_relocate(myl_rc_slot *destination, myl_rc_slot *source) {
    myl_rc_invariant(destination && source && destination->shape && source->shape);
    myl_rc_invariant(destination->shape->size == source->shape->size);
    size_t bytes = source->shape->size;
    if (destination->address == source->address) return;
    uintptr_t dst = (uintptr_t)destination->address, src = (uintptr_t)source->address;
    myl_rc_invariant(dst > src ? dst - src >= bytes : src - dst >= bytes);
    memcpy(destination->address, source->address, bytes);
    memset(source->address, 0, bytes);
}

void myl_rc_value_seed(myl_native_heap *heap, const myl_rc_shape *source_shape,
                        void *destination, const void *source, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && destination != source);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, source_shape);
    size_t bytes;
    myl_rc_invariant(shape != NULL);
    myl_rc_invariant(myl_rc_size_mul(shape->size, count, &bytes));
    memcpy(destination, source, bytes);
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    unsigned char *cursor = destination;
    for (size_t i = 0; i < count; ++i) {
        push(heap, shape, cursor);
        walk(heap, WALK_CLEAR);
        cursor += shape->size;
    }
}
void myl_rc_construction_abort(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    myl_native_object *header = (myl_native_object *)payload - 1;
    myl_rc_invariant(!(header->mark & MYL_NATIVE_OBJECT_IMMORTAL));
    if (!(header->mark & MYL_NATIVE_OBJECT_ARENA)) { myl_rc_owner_release(heap, payload); return; }
    if (header->mark & MYL_RC_OBJECT_DYING) return;
    header->mark |= MYL_RC_OBJECT_DYING;
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(heap, header->element);
    myl_rc_invariant(descriptor != NULL);
    size_t count = (header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) & MYL_NATIVE_ARENA_COUNT_MAX;
    if (descriptor->finalize) descriptor->finalize(heap, payload);
    descriptor = myl_rc_descriptor_find(heap, header->element);
    if (descriptor->edges) descriptor->edges(heap, payload, count);
    else myl_rc_edges_release(heap, descriptor->shape, payload, count);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(header->element->size, count, &bytes));
    memset(payload, 0, bytes);
    myl_rc_drain(heap);
}
static void unique_push(myl_native_heap *heap, const myl_native_type *type, unsigned char *address,
                          myl_native_drop_link **work) {
    if (type->kind == MYL_NATIVE_RESOURCE) {
        myl_native_resource *resource;
        memcpy(&resource, address, sizeof resource);
        memset(address, 0, sizeof resource);
        if (resource) {
            resource->work = (myl_native_drop_link){.next = *work, .owner = resource, .kind = type->kind};
            *work = &resource->work;
        }
    } else if (type->kind == MYL_NATIVE_ARRAY || type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
        heap->rc->walk.frames[heap->rc->walk.depth++] = (myl_rc_frame){.type = type, .address = address};
    }
}
void myl_rc_owned_drop(myl_native_heap *heap, const myl_native_type *type, void *value) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    myl_native_drop_link *work = NULL;
    unique_push(heap, type, value, &work);
    while (heap->rc->walk.depth) {
        myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
        type = frame->type;
        if (type->kind == MYL_NATIVE_ARRAY) {
            if (frame->cursor == type->count) { --heap->rc->walk.depth; continue; }
            size_t offset = frame->cursor++ * type->stride;
            unique_push(heap, type->fields[0].type, frame->address + offset, &work);
        } else {
            if (frame->cursor == type->field_count) { --heap->rc->walk.depth; continue; }
            const myl_native_field *field = &type->fields[frame->cursor++];
            if (type->kind == MYL_NATIVE_VARIANT) {
                uint32_t tag;
                memcpy(&tag, frame->address, sizeof tag);
                if (tag != field->tag) continue;
            }
            unique_push(heap, field->type, frame->address + field->offset, &work);
        }
    }
    /* All token slots are disarmed before the first callback. The intrusive
     * schedule is independent of metadata and stays valid if a close hook
     * allocates, registers descriptors, or starts another unique traversal. */
    while (work) {
        myl_native_resource *resource = work->owner;
        work = work->next;
        resource->drop(resource);
    }
}
void myl_rc_finalize_unique(myl_native_heap *heap, void *payload) {
    const myl_native_object *header = (const myl_native_object *)payload - 1;
    size_t count = (header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) &
        (header->mark & MYL_NATIVE_OBJECT_ARENA ? MYL_NATIVE_ARENA_COUNT_MAX : MYL_NATIVE_OBJECT_COUNT_MAX);
    myl_rc_invariant(!heap->rc->walk.depth);
    for (size_t i = 0; i < count; ++i)
        myl_rc_owned_drop(heap, header->element, (unsigned char *)payload + i * header->element->size);
}
