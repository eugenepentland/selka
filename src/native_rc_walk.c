#include "native_rc_internal.h"
#include <string.h>

static void push(myl_native_heap *heap, const myl_rc_shape *shape, unsigned char *address) {
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
    myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth++];
    *frame = (myl_rc_frame){.shape = shape, .address = address};
}
/* Frames keep the next child/index, not an expanded list of array elements. */
enum { WALK_CLEAR, WALK_RELEASE, WALK_REGION, WALK_UNLOAN };
static unsigned walk(myl_native_heap *heap, unsigned action) {
    unsigned region = 0;
    while (heap->rc->walk.depth) {
        myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
        const myl_rc_shape *shape = frame->shape;
        if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) {
            void *payload;
            memcpy(&payload, frame->address, sizeof payload);
            if (action == WALK_REGION) {
                unsigned found = payload ? myl_native_header_region(payload) : 0;
                if (found > region) region = found;
            } else memset(frame->address, 0, sizeof payload);
            --heap->rc->walk.depth;
            if (action == WALK_RELEASE || action == WALK_UNLOAN) {
                if (shape->kind == MYL_RC_SHAPE_HOLD_POINTER || action == WALK_UNLOAN) {
                    myl_rc_hold hold = {.payload = payload};
                    myl_rc_hold_release(heap, &hold);
                } else myl_rc_edge_release(heap, payload);
            }
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
/* Release every live leaf of one shallow value (see myl_rc_shallow): clear
 * each edge, then drop its O or H token, enqueueing any death. `unloan`
 * drops H for every leaf. The caller drains. */
static void shallow_release(myl_native_heap *heap, const myl_rc_shape *shape, unsigned char *address, int unloan) {
    myl_rc_shallow leaves;
    myl_rc_shallow_begin(&leaves, shape, address);
    size_t offset;
    myl_rc_shape_kind kind;
    while (myl_rc_shallow_next(&leaves, &offset, &kind)) {
        void *payload;
        memcpy(&payload, address + offset, sizeof payload);
        memset(address + offset, 0, sizeof payload);
        if (unloan || kind == MYL_RC_SHAPE_HOLD_POINTER) myl_rc_hold_drop(heap, payload);
        else myl_rc_owner_drop(heap, payload);
    }
}
unsigned myl_rc_value_region(myl_native_heap *heap, const myl_rc_shape *source, const void *address) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);
    myl_rc_invariant(shape && (!shape->size || address));
    if (myl_rc_shallow_admits(shape)) {
        myl_rc_shallow leaves;
        myl_rc_shallow_begin(&leaves, shape, address);
        size_t offset;
        myl_rc_shape_kind kind;
        unsigned region = 0;
        while (myl_rc_shallow_next(&leaves, &offset, &kind)) {
            void *payload;
            memcpy(&payload, (const unsigned char *)address + offset, sizeof payload);
            unsigned found = payload ? myl_native_header_region(payload) : 0;
            if (found > region) region = found;
        }
        return region;
    }
    push(heap, shape, (unsigned char *)address);
    return walk(heap, WALK_REGION);
}
void myl_rc_edges_release(myl_native_heap *heap, const myl_rc_shape *source, void *address, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);
    myl_rc_invariant(shape != NULL);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(shape->size, count, &bytes));
    myl_rc_invariant(!bytes || address);
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    unsigned char *cursor = address;
    int shallow = myl_rc_shallow_admits(shape);
    for (size_t i = 0; i < count; ++i) {
        if (shallow) shallow_release(heap, shape, cursor, 0);
        else {
            push(heap, shape, cursor);
            walk(heap, WALK_RELEASE);
        }
        cursor += shape->size;
    }
}
void myl_rc_flat_edges_release(myl_native_heap *heap, const myl_rc_binding *binding, void *address, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && binding->flat.count <= MYL_RC_FLAT_LEAVES);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(binding->flat.size, count, &bytes) && (!bytes || address));
    if (!binding->flat.count) return;
    unsigned char *cursor = address;
    for (size_t i = 0; i < count; ++i) {
        myl_rc_flat_release_one(heap, &binding->flat, cursor);
        cursor += binding->flat.size;
    }
}
/* Bindings are immutable batch allocations published through the binding map
 * and never replaced. A generic callback may register metadata; the binding is
 * looked up again after it returns. */
void myl_rc_drain(myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc);
    myl_rc_state *rc = heap->rc;
    if (!rc->dead.head || rc->dead.active || rc->walk.depth) return;
    rc->dead.active = 1;
    /* A type's binding never changes once published, so the previous death's
     * binding answers a repeated type without a probe. */
    const myl_native_type *last = NULL;
    const myl_rc_binding *binding = NULL;
    while (rc->dead.head) {
        myl_rc_object *object = rc->dead.head;
        rc->dead.head = (myl_rc_object *)object->owners;
        void *payload = object + 1;
        if (object->common.element != last) {
            last = object->common.element;
            binding = myl_rc_binding_find(heap, last);
            myl_rc_invariant(binding != NULL);
        }
        size_t count = (size_t)((object->common.mark & MYL_NATIVE_OBJECT_COUNT_BITS) >> MYL_NATIVE_OBJECT_COUNT_SHIFT);
        if (binding->flat.count <= MYL_RC_FLAT_LEAVES) {
            /* Admission excludes every custom hook. No callback can invalidate
             * metadata here; ordered ordinary edges only enqueue more work. */
            if (binding->flat.count) {
                if (count == 1) myl_rc_flat_release_one(heap, &binding->flat, payload);
                else myl_rc_flat_edges_release(heap, binding, payload, count);
            }
        } else {
            /* A unique close hook can inspect its managed context. Run it while
             * child tokens are intact, with no descriptor frame leased. Nested
             * releases only enqueue. Reacquire metadata after a registering hook. */
            void (*finalize)(myl_native_heap *, void *) = binding->descriptor.finalize;
            if (finalize) finalize(heap, payload);
            binding = myl_rc_binding_find(heap, object->common.element);
            myl_rc_invariant(binding && !rc->walk.depth);
            if (binding->descriptor.edges) binding->descriptor.edges(heap, payload, count);
            else myl_rc_edges_release(heap, binding->descriptor.shape, payload, count);
        }
        myl_rc_invariant(!rc->walk.depth);
        myl_rc_retire(heap, object);
    }
    rc->dead.active = 0;
}
void myl_rc_value_drop(myl_native_heap *heap, myl_rc_slot *slot) {
    myl_rc_invariant(slot && slot->shape && slot->address);
    myl_rc_edges_release(heap, slot->shape, slot->address, 1);
    memset(slot->address, 0, slot->shape->size);
    myl_rc_drain(heap);
}
void myl_rc_loan_drop(myl_native_heap *heap, const myl_rc_shape *source, void *address) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);
    myl_rc_invariant(shape && (!shape->size || address));
    if (myl_rc_shallow_admits(shape)) shallow_release(heap, shape, address, 1);
    else {
        push(heap, shape, address);
        walk(heap, WALK_UNLOAN);
    }
    memset(address, 0, shape->size);
    myl_rc_drain(heap);
}
/* Registration reserved the full inline depth, including count-free native
 * records. Check every variant arm without reading a value or closing a token. */
int myl_rc_native_has_unique(myl_native_heap *heap, const myl_native_type *type) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    for (;;) {
        if (type->kind == MYL_NATIVE_POINTER && type->collection_kind == 5 && type->element) {
            const myl_rc_descriptor *body = myl_rc_descriptor_of(heap, type->element);
            myl_rc_invariant(body != NULL);
            if (body->finalize) { heap->rc->walk.depth = 0; return 1; }
        }
        if (type->kind == MYL_NATIVE_RESOURCE || type->kind == MYL_NATIVE_OWNED_BUFFER ||
            type->kind == MYL_NATIVE_OWNED_POOL) { heap->rc->walk.depth = 0; return 1; }
        if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT || type->kind == MYL_NATIVE_ARRAY) {
            myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
            heap->rc->walk.frames[heap->rc->walk.depth++] = (myl_rc_frame){.type = type};
        }
        for (;;) {
            if (!heap->rc->walk.depth) return 0;
            myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
            size_t count = frame->type->kind == MYL_NATIVE_ARRAY ? (frame->type->count ? 1 : 0) : frame->type->field_count;
            if (frame->cursor < count) { type = frame->type->fields[frame->cursor++].type; break; }
            --heap->rc->walk.depth;
        }
    }
}
int myl_rc_binding_has_unique(myl_native_heap *heap, const myl_rc_binding *binding) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && binding);
    unsigned fact = binding->flat.native_unique;
    if (!fact) {
        /* No callback or registration occurs in this walk. In particular, a
         * missing typed-box body must fail before a negative fact is published. */
        fact = myl_rc_native_has_unique(heap, binding->descriptor.type) ? 2 : 1;
        ((myl_rc_binding *)binding)->flat.native_unique = (unsigned char)fact;
    }
    myl_rc_invariant(fact <= 2);
    return fact == 2;
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
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source_shape);
    size_t bytes;
    myl_rc_invariant(shape != NULL);
    myl_rc_invariant(myl_rc_size_mul(shape->size, count, &bytes));
    if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) {
        memset(destination, 0, bytes);
        return;
    }
    memcpy(destination, source, bytes);
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    unsigned char *cursor = destination;
    int shallow = myl_rc_shallow_admits(shape);
    for (size_t i = 0; i < count; ++i) {
        if (shallow) {
            myl_rc_shallow leaves;
            myl_rc_shallow_begin(&leaves, shape, cursor);
            size_t offset;
            myl_rc_shape_kind kind;
            while (myl_rc_shallow_next(&leaves, &offset, &kind)) memset(cursor + offset, 0, sizeof(void *));
        } else {
            push(heap, shape, cursor);
            walk(heap, WALK_CLEAR);
        }
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
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_of(heap, header->element);
    myl_rc_invariant(descriptor != NULL);
    size_t count = (header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) & MYL_NATIVE_ARENA_COUNT_MAX;
    if (descriptor->finalize) descriptor->finalize(heap, payload);
    descriptor = myl_rc_descriptor_of(heap, header->element);
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
