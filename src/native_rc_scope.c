#include "native_rc_internal.h"
#include <string.h>

typedef struct scope_entry {
    struct scope_entry *previous;
    myl_rc_pin pin;
    unsigned pinned;
} scope_entry;
static void restore(scope_entry *entry) {
    if (!entry->pinned || !entry->pin.hold.payload) return;
    myl_native_object *header = (myl_native_object *)entry->pin.hold.payload - 1;
    if (!(header->mark & MYL_NATIVE_OBJECT_IMMORTAL))
        header->mark = (header->mark & ~MYL_NATIVE_OBJECT_PINNED) | entry->pin.previous;
}
/* Restore every bit before any final hold can run a destructor or callback. */
static void unwind(myl_rc_scope *scope, scope_entry *boundary) {
    scope_entry *head = scope->journal;
    for (scope_entry *entry = head; entry != boundary; entry = entry->previous) restore(entry);
    scope->journal = boundary;
    while (head != boundary) {
        scope_entry *entry = head;
        head = entry->previous;
        myl_rc_hold_release(scope->heap, &entry->pin.hold);
        myl_rc_meta_free(scope->heap, entry, sizeof *entry);
    }
}
void myl_rc_scope_begin(myl_native_heap *heap, myl_rc_scope *scope) {
    myl_rc_invariant(heap && heap->rc && scope);
    *scope = (myl_rc_scope){.heap = heap, .previous = heap->rc->scopes, .active = 1, .region = heap->region_depth};
    heap->rc->scopes = scope;
}
static myl_rc_status capture(myl_rc_scope *scope, void *payload, unsigned pinned) {
    myl_rc_invariant(scope && scope->active && scope->heap && scope->heap->rc);
    if (!payload) return MYL_RC_OK;
    myl_native_object *header = (myl_native_object *)payload - 1;
    if (header->mark & MYL_NATIVE_OBJECT_IMMORTAL) return MYL_RC_OK;
    /* An outer receiver may span younger callbacks, but it cannot acquire a
     * hold that pretends to extend a younger arena's chunk lifetime. */
    if (myl_native_header_region(payload) > scope->region) return MYL_RC_REGION_ERROR;
    scope_entry *entry = myl_rc_meta_alloc(scope->heap, sizeof *entry);
    if (!entry) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_status status = pinned ? myl_rc_pin_acquire(scope->heap, payload, &entry->pin) :
        myl_rc_hold_acquire(scope->heap, payload, &entry->pin.hold);
    if (status != MYL_RC_OK) { myl_rc_meta_free(scope->heap, entry, sizeof *entry); return status; }
    entry->previous = scope->journal;
    entry->pinned = pinned;
    scope->journal = entry;
    return MYL_RC_OK;
}
myl_rc_status myl_rc_scope_hold(myl_rc_scope *scope, void *payload) { return capture(scope, payload, 0); }
myl_rc_status myl_rc_scope_pin(myl_rc_scope *scope, void *payload) { return capture(scope, payload, 1); }
myl_rc_status myl_rc_scope_extend(myl_rc_scope *scope, void *boundary,
                                   myl_rc_status (*extend)(myl_rc_scope *, void *)) {
    /* The adapter may append holds. Follow only the original prefix, whose
     * nodes remain stable, and roll the complete prefix back on refusal. */
    for (scope_entry *entry = scope->journal; entry != boundary; entry = entry->previous) {
        myl_rc_invariant(entry != NULL);
        myl_rc_status status = extend(scope, entry->pin.hold.payload);
        if (status != MYL_RC_OK) { unwind(scope, boundary); return status; }
    }
    return MYL_RC_OK;
}
void myl_rc_scope_end(myl_rc_scope *scope) {
    myl_rc_invariant(scope != NULL);
    if (!scope->active) return;
    myl_native_heap *heap = scope->heap;
    myl_rc_invariant(heap && heap->rc && heap->rc->scopes == scope);
    heap->rc->scopes = scope->previous;
    scope->active = 0;
    scope->previous = NULL;
    unwind(scope, NULL);
    myl_rc_drain(heap);
}
void myl_rc_scopes_close_region(myl_native_heap *heap, unsigned region) {
    myl_rc_scope *boundary = heap->rc->scopes;
    while (boundary && boundary->region >= region) boundary = boundary->previous;
    myl_rc_scope_unwind(heap, boundary);
}
myl_rc_scope *myl_rc_scope_current(myl_native_heap *heap) {
    return heap && heap->rc ? heap->rc->scopes : NULL;
}
void myl_rc_scope_unwind(myl_native_heap *heap, myl_rc_scope *checkpoint) {
    if (!heap || !heap->rc) { myl_rc_invariant(!checkpoint); return; }
    for (myl_rc_scope *scope = heap->rc->scopes; scope != checkpoint; scope = scope->previous) {
        myl_rc_invariant(scope != NULL);
        for (scope_entry *entry = scope->journal; entry; entry = entry->previous) {
            restore(entry);
            entry->pinned = 0;
        }
    }
    while (heap->rc->scopes != checkpoint) myl_rc_scope_end(heap->rc->scopes);
}
typedef struct {
    const myl_rc_shape *shape;
    unsigned char *address;
    size_t step, cursor;
    unsigned region;
} prepare_frame;
static const myl_rc_shape *member(const myl_rc_shape *shape, const void *address, size_t offset) {
    myl_rc_invariant(shape->kind == MYL_RC_SHAPE_RECORD || shape->kind == MYL_RC_SHAPE_VARIANT);
    const myl_rc_field *fields = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.fields : shape->as.variant.fields;
    size_t count = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.count : shape->as.variant.count;
    uint32_t tag = 0;
    if (shape->kind == MYL_RC_SHAPE_VARIANT)
        memcpy(&tag, (const unsigned char *)address + shape->as.variant.tag_offset, sizeof tag);
    for (size_t i = 0; i < count; ++i)
        if (fields[i].offset == offset && (shape->kind != MYL_RC_SHAPE_VARIANT || fields[i].tag == tag)) return fields[i].shape;
    myl_rc_invariant(0);
    return NULL;
}
static myl_rc_status prepare_leaf(myl_rc_scope *scope, prepare_frame *frame) {
    if (frame->shape->kind == MYL_RC_SHAPE_NONE) return MYL_RC_OK;
    myl_rc_invariant(frame->shape->kind == MYL_RC_SHAPE_POINTER || frame->shape->kind == MYL_RC_SHAPE_HOLD_POINTER);
    myl_rc_slot slot = {.shape = frame->shape, .address = frame->address, .region = frame->region};
    void *payload;
    memcpy(&payload, frame->address, sizeof payload);
    /* Inline paths have no managed container from which to recover their
     * binding lifetime. Preserve each existing leaf's older allocation region
     * instead of moving it into the arena of the call that prepares it. */
    unsigned origin = payload ? myl_native_header_region(payload) : 0;
    if (origin < slot.region) slot.region = origin;
    myl_rc_status status = frame->shape->kind == MYL_RC_SHAPE_HOLD_POINTER ?
        myl_rc_unique_held(scope->heap, &slot) : myl_rc_unique_owned(scope->heap, &slot);
    if (status != MYL_RC_OK) return status;
    memcpy(&payload, frame->address, sizeof payload);
    return myl_rc_scope_pin(scope, payload);
}
static myl_rc_status prepare_path(myl_rc_scope *scope, const myl_rc_place *place, prepare_frame *frames) {
    const myl_rc_shape *shape = myl_rc_shape_resolve(scope->heap, place->receiver.shape);
    myl_rc_invariant(shape != NULL);
    frames[0] = (prepare_frame){.shape = shape, .address = place->receiver.address, .region = place->receiver.region};
    size_t used = 1;
    while (used) {
        prepare_frame *frame = &frames[used - 1];
        if (frame->step == place->count) {
            myl_rc_status status = prepare_leaf(scope, frame);
            if (status != MYL_RC_OK) return status;
            --used;
            continue;
        }
        const myl_rc_projection *projection = &place->path[frame->step];
        shape = myl_rc_shape_resolve(scope->heap, projection->shape);
        myl_rc_invariant(shape && shape->size == frame->shape->size);
        if (shape->kind == MYL_RC_SHAPE_ARRAY) {
            if (frame->cursor == shape->as.array.count) { --used; continue; }
            frames[used++] = (prepare_frame){.shape = shape->as.array.element,
                .address = frame->address + frame->cursor++ * shape->as.array.stride,
                .step = frame->step + 1, .region = frame->region};
            continue;
        }
        if (frame->cursor++) { --used; continue; }
        unsigned char *address = frame->address;
        unsigned region = frame->region;
        if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) {
            myl_rc_status status = prepare_leaf(scope, frame);
            if (status != MYL_RC_OK) return status;
            void *payload;
            memcpy(&payload, address, sizeof payload);
            if (!payload) { --used; continue; }
            const myl_native_object *header = (const myl_native_object *)payload - 1;
            const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(scope->heap, header->element);
            myl_rc_invariant(descriptor != NULL);
            address = payload;
            region = myl_native_header_region(payload);
            shape = descriptor->shape;
        }
        const myl_rc_shape *child = member(shape, address, projection->offset);
        frames[used++] = (prepare_frame){.shape = child, .address = address + projection->offset,
            .step = frame->step + 1, .region = region};
    }
    return MYL_RC_OK;
}
myl_rc_status myl_rc_scope_prepare(myl_rc_scope *scope, const myl_rc_place *place) {
    myl_rc_invariant(scope && scope->active && place && place->receiver.address && (!place->count || place->path));
    size_t count, bytes;
    if (!myl_rc_size_add(place->count, 1, &count) || !myl_rc_size_mul(count, sizeof(prepare_frame), &bytes))
        return MYL_RC_ALLOCATION_REFUSED;
    prepare_frame *frames = myl_rc_meta_alloc(scope->heap, bytes);
    if (!frames) return MYL_RC_ALLOCATION_REFUSED;
    scope_entry *boundary = scope->journal;
    myl_rc_status status = myl_rc_scope_hold(scope, place->receiver.container);
    if (status == MYL_RC_OK) status = prepare_path(scope, place, frames);
    myl_rc_meta_free(scope->heap, frames, bytes);
    if (status != MYL_RC_OK) unwind(scope, boundary);
    return status;
}
