#include "native_rc_internal.h"
#include <string.h>

typedef struct {
    const myl_rc_shape *shape;
    unsigned char *destination;
    const unsigned char *source;
    size_t cursor;
} transfer_frame;
typedef struct {
    const void *source;
    void *destination;
    const myl_rc_descriptor *descriptor;
    size_t cursor;
    unsigned region;
} clone_frame;
typedef struct {
    clone_frame *items;
    size_t count, capacity;
    void **arenas;
    size_t arena_count, arena_capacity;
} clone_work;
typedef struct {
    myl_native_heap *heap;
    transfer_frame *frames;
    size_t capacity, depth;
    unsigned region;
    myl_rc_transfer mode;
    clone_work *clones;
} transfer_walk;
typedef myl_rc_status (*pointer_action)(transfer_walk *, unsigned char *, const unsigned char *);

static void push(transfer_walk *walk, const myl_rc_shape *shape, unsigned char *destination, const unsigned char *source) {
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    myl_rc_invariant(walk->depth < walk->capacity);
    walk->frames[walk->depth++] = (transfer_frame){.shape = shape, .destination = destination, .source = source};
}
/* Fallible operations have their own frames. A clone callback may allocate or
 * register another descriptor; it never borrows or resizes these frames. */
static myl_rc_status visit(transfer_walk *walk, const myl_rc_shape *shape, void *destination,
                           const void *source, pointer_action action) {
    walk->depth = 0;
    if (shape->kind == MYL_RC_SHAPE_POINTER) return action(walk, destination, source);
    push(walk, shape, destination, source);
    while (walk->depth) {
        transfer_frame *frame = &walk->frames[walk->depth - 1];
        shape = frame->shape;
        if (shape->kind == MYL_RC_SHAPE_POINTER) {
            myl_rc_status status = action(walk, frame->destination, frame->source);
            if (status != MYL_RC_OK) { walk->depth = 0; return status; }
            --walk->depth;
        } else if (shape->kind == MYL_RC_SHAPE_ARRAY) {
            if (frame->cursor == shape->as.array.count) { --walk->depth; continue; }
            size_t offset = frame->cursor++ * shape->as.array.stride;
            push(walk, shape->as.array.element, frame->destination + offset, frame->source + offset);
        } else {
            const myl_rc_field *fields = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.fields : shape->as.variant.fields;
            size_t count = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.count : shape->as.variant.count;
            if (frame->cursor == count) { --walk->depth; continue; }
            const myl_rc_field *field = &fields[frame->cursor++];
            if (shape->kind == MYL_RC_SHAPE_VARIANT) {
                uint32_t tag;
                memcpy(&tag, frame->source + shape->as.variant.tag_offset, sizeof tag);
                if (tag != field->tag) continue;
            }
            push(walk, field->shape, frame->destination + field->offset, frame->source + field->offset);
        }
    }
    return MYL_RC_OK;
}
static void *reserve_items(myl_native_heap *heap, void *old, size_t *capacity, size_t used, size_t width) {
    if (used < *capacity) return old;
    size_t grown = *capacity ? *capacity * 2 : 16, bytes;
    if (grown < *capacity || !myl_rc_size_mul(grown, width, &bytes)) return NULL;
    void *items = myl_rc_meta_alloc(heap, bytes);
    if (!items) return NULL;
    if (used) memcpy(items, old, used * width);
    myl_rc_meta_free(heap, old, *capacity * width);
    *capacity = grown;
    return items;
}
static size_t payload_count(const void *payload) {
    uintptr_t mark = ((const myl_native_object *)payload - 1)->mark;
    return (mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) &
        (mark & MYL_NATIVE_OBJECT_ARENA ? MYL_NATIVE_ARENA_COUNT_MAX : MYL_NATIVE_OBJECT_COUNT_MAX);
}
static myl_rc_status schedule_clone(transfer_walk *walk, const void *payload, unsigned region, void **out) {
    *out = NULL;
    clone_work *work = walk->clones;
    const myl_native_object *common = (const myl_native_object *)payload - 1;
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(walk->heap, common->element);
    myl_rc_invariant(descriptor && !descriptor->finalize);
    myl_rc_invariant(descriptor->shell || descriptor->edges == NULL);
    int pending = descriptor->next || (!descriptor->shell && descriptor->shape->kind != MYL_RC_SHAPE_NONE);
    if (pending) {
        clone_frame *items = reserve_items(walk->heap, work->items, &work->capacity, work->count, sizeof *items);
        if (!items) return MYL_RC_ALLOCATION_REFUSED;
        work->items = items;
    }
    if (region) {
        void **arenas = reserve_items(walk->heap, work->arenas, &work->arena_capacity, work->arena_count, sizeof *arenas);
        if (!arenas) return MYL_RC_ALLOCATION_REFUSED;
        work->arenas = arenas;
    }
    void *copy = NULL;
    myl_rc_status status;
    if (descriptor->shell) status = descriptor->shell(walk->heap, payload, region, &copy);
    else {
        myl_rc_alloc_request request = {.element = common->element, .count = payload_count(payload), .region = region};
        status = myl_rc_new(walk->heap, &request, &copy);
        if (status == MYL_RC_OK) myl_rc_value_seed(walk->heap, descriptor->shape, copy, payload, request.count);
    }
    if (status != MYL_RC_OK) return status;
    myl_rc_invariant(copy != NULL);
    MYL_RC_STAT(walk->heap, MYL_RC_STAT_CLONE);
    if (pending)
        work->items[work->count++] = (clone_frame){.source = payload, .destination = copy, .descriptor = descriptor, .region = region};
    if (region) work->arenas[work->arena_count++] = copy;
    *out = copy;
    return MYL_RC_OK;
}
static myl_rc_status transfer_pointer(transfer_walk *walk, unsigned char *destination, const unsigned char *source) {
    void *payload, *result;
    memcpy(&payload, source, sizeof payload);
    result = payload;
    if (payload) {
        myl_native_object *common = (myl_native_object *)payload - 1;
        uintptr_t mark = common->mark;
        if (!(mark & MYL_NATIVE_OBJECT_IMMORTAL)) {
            unsigned region = mark & MYL_NATIVE_OBJECT_ARENA ? myl_native_header_region(payload) : 0;
            if (region > walk->region) return MYL_RC_REGION_ERROR;
            if (mark & MYL_NATIVE_OBJECT_PINNED) {
                myl_rc_status status = schedule_clone(walk, payload, walk->region, &result);
                if (status != MYL_RC_OK) return status;
            } else if (walk->mode == MYL_RC_COPY) {
                if (region) common->mark |= MYL_NATIVE_OBJECT_SHARED;
                else {
                    myl_rc_status status = myl_rc_owner_acquire(walk->heap, payload);
                    if (status != MYL_RC_OK) return status;
                }
            }
        }
    }
    memcpy(destination, &result, sizeof result);
    return MYL_RC_OK;
}
/* In a TAKE staging value only differing pointers are new clone tokens. The
 * unchanged words still borrow the source tokens until the transaction commits. */
static myl_rc_status rollback_take(transfer_walk *walk, unsigned char *destination, const unsigned char *source) {
    void *old, *fresh;
    memcpy(&old, source, sizeof old);
    memcpy(&fresh, destination, sizeof fresh);
    if (old != fresh) myl_rc_edge_release(walk->heap, fresh);
    return MYL_RC_OK;
}
static myl_rc_status commit_take(transfer_walk *walk, unsigned char *destination, const unsigned char *source) {
    void *old, *fresh;
    memcpy(&old, source, sizeof old);
    memcpy(&fresh, destination, sizeof fresh);
    if (old != fresh) myl_rc_edge_release(walk->heap, old);
    return MYL_RC_OK;
}
static myl_rc_status prepare_frames(transfer_walk *walk, const myl_rc_shape *shape) {
    size_t needed = myl_rc_shape_depth(walk->heap, shape), bytes;
    if (needed <= 1 || needed <= walk->capacity) return MYL_RC_OK;
    myl_rc_invariant(!walk->depth);
    myl_rc_invariant(myl_rc_size_mul(needed, sizeof(transfer_frame), &bytes));
    transfer_frame *frames = myl_rc_meta_alloc(walk->heap, bytes);
    if (!frames) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_meta_free(walk->heap, walk->frames, walk->capacity * sizeof *frames);
    walk->frames = frames;
    walk->capacity = needed;
    return MYL_RC_OK;
}
static int clone_next(transfer_walk *walk, clone_frame *frame, myl_rc_slot *to, myl_rc_slot *from) {
    if (frame->descriptor->next)
        return frame->descriptor->next(walk->heap, frame->source, frame->destination, &frame->cursor, to, from);
    if (frame->cursor == payload_count(frame->source)) return 0;
    const myl_rc_shape *shape = frame->descriptor->shape;
    size_t offset = frame->cursor++ * shape->size;
    *to = (myl_rc_slot){.shape = shape, .address = (unsigned char *)frame->destination + offset,
        .container = frame->destination, .region = frame->region};
    *from = (myl_rc_slot){.shape = shape, .address = (unsigned char *)frame->source + offset,
        .container = (void *)frame->source};
    return 1;
}
/* A clone frame finishes one direct value before resuming its next cursor.
 * New pinned children append frames; no clone calls copy recursively. */
static myl_rc_status finish_clones(transfer_walk *walk) {
    clone_work *work = walk->clones;
    walk->mode = MYL_RC_COPY;
    while (work->count) {
        myl_rc_slot to, from;
        clone_frame *frame = &work->items[work->count - 1];
        if (!clone_next(walk, frame, &to, &from)) { --work->count; continue; }
        const myl_rc_shape *shape = myl_rc_shape_resolve(walk->heap, from.shape);
        myl_rc_invariant(shape && to.shape && to.shape->size == shape->size);
        myl_rc_status status = prepare_frames(walk, shape);
        if (status != MYL_RC_OK) return status;
        walk->region = to.region;
        myl_rc_value_seed(walk->heap, shape, to.address, from.address, 1);
        status = visit(walk, shape, to.address, from.address, transfer_pointer);
        if (status != MYL_RC_OK) return status;
    }
    return MYL_RC_OK;
}
static void dispose_walk(transfer_walk *walk, int failed) {
    clone_work *work = walk->clones;
    if (failed)
        for (size_t i = 0; i < work->arena_count; ++i)
            myl_rc_construction_abort(walk->heap, work->arenas[i]);
    myl_rc_meta_free(walk->heap, work->arenas, work->arena_capacity * sizeof *work->arenas);
    myl_rc_meta_free(walk->heap, work->items, work->capacity * sizeof *work->items);
    myl_rc_meta_free(walk->heap, walk->frames, walk->capacity * sizeof *walk->frames);
    myl_rc_drain(walk->heap);
}
static myl_rc_status clone_payload(myl_native_heap *heap, const void *payload, unsigned region, void **out) {
    clone_work work = {0};
    transfer_walk walk = {.heap = heap, .clones = &work, .region = region, .mode = MYL_RC_COPY};
    void *copy = NULL;
    myl_rc_status status = schedule_clone(&walk, payload, region, &copy);
    if (status == MYL_RC_OK) status = finish_clones(&walk);
    if (status != MYL_RC_OK && copy && !region) myl_rc_owner_release(heap, copy);
    dispose_walk(&walk, status != MYL_RC_OK);
    *out = status == MYL_RC_OK ? copy : NULL;
    return status;
}
static myl_rc_status transfer(myl_native_heap *heap, myl_rc_slot *destination,
                              const myl_rc_slot *source, myl_rc_transfer mode) {
    myl_rc_invariant(heap && heap->rc && destination && source && destination->address && source->address);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, source->shape);
    const myl_rc_shape *target = myl_rc_shape_resolve(heap, destination->shape);
    myl_rc_invariant(shape && target && shape->size == target->size && source->address != destination->address);
    if (destination->region > heap->region_depth) return MYL_RC_REGION_ERROR;
    clone_work work = {0};
    transfer_walk walk = {.heap = heap, .region = destination->region, .mode = mode, .clones = &work};
    myl_rc_status status = prepare_frames(&walk, shape);
    if (status != MYL_RC_OK) return status;
    if (mode == MYL_RC_COPY) myl_rc_value_seed(heap, shape, destination->address, source->address, 1);
    else memcpy(destination->address, source->address, shape->size);
    status = visit(&walk, shape, destination->address, source->address, transfer_pointer);
    if (status == MYL_RC_OK) status = finish_clones(&walk);
    if (status != MYL_RC_OK) {
        if (mode == MYL_RC_COPY) myl_rc_edges_release(heap, shape, destination->address, 1);
        else (void)visit(&walk, shape, destination->address, source->address, rollback_take);
        memset(destination->address, 0, shape->size);
    } else if (mode == MYL_RC_TAKE) {
        (void)visit(&walk, shape, destination->address, source->address, commit_take);
        memset(source->address, 0, shape->size);
    }
    dispose_walk(&walk, status != MYL_RC_OK);
    return status;
}
myl_rc_status myl_rc_value_copy(myl_native_heap *heap, myl_rc_slot *destination, const myl_rc_slot *source) {
    return transfer(heap, destination, source, MYL_RC_COPY);
}
myl_rc_status myl_rc_value_copy_many(myl_native_heap *heap, myl_rc_slot *destinations,
                                     const myl_rc_slot *sources, size_t count) {
    myl_rc_invariant(heap && heap->rc && (!count || (destinations && sources)));
    clone_work work = {0};
    transfer_walk walk = {.heap = heap, .mode = MYL_RC_COPY, .clones = &work};
    size_t initialized = 0;
    myl_rc_status status = MYL_RC_OK;
    for (size_t i = 0; i < count; ++i) {
        const myl_rc_shape *shape = myl_rc_shape_resolve(heap, sources[i].shape);
        const myl_rc_shape *target = myl_rc_shape_resolve(heap, destinations[i].shape);
        myl_rc_invariant(shape && target && shape->size == target->size && sources[i].address != destinations[i].address);
        if (destinations[i].region > heap->region_depth) { status = MYL_RC_REGION_ERROR; break; }
        status = prepare_frames(&walk, shape);
        if (status != MYL_RC_OK) break;
        myl_rc_value_seed(heap, shape, destinations[i].address, sources[i].address, 1);
        ++initialized;
        walk.region = destinations[i].region;
        status = visit(&walk, shape, destinations[i].address, sources[i].address, transfer_pointer);
        if (status != MYL_RC_OK) break;
    }
    if (status == MYL_RC_OK) status = finish_clones(&walk);
    if (status != MYL_RC_OK)
        for (size_t i = 0; i < initialized; ++i) {
            myl_rc_edges_release(heap, destinations[i].shape, destinations[i].address, 1);
            memset(destinations[i].address, 0, destinations[i].shape->size);
        }
    dispose_walk(&walk, status != MYL_RC_OK);
    return status;
}
myl_rc_status myl_rc_value_take(myl_native_heap *heap, myl_rc_slot *destination, myl_rc_slot *source) {
    return transfer(heap, destination, source, MYL_RC_TAKE);
}
myl_rc_status myl_rc_value_replace(myl_native_heap *heap, myl_rc_slot *destination,
                                   myl_rc_slot *source, myl_rc_transfer mode) {
    myl_rc_invariant(destination && source && destination->shape && source->shape);
    if (destination->address == source->address) return MYL_RC_OK;
    size_t size = destination->shape->size, bytes;
    myl_rc_invariant(size == source->shape->size);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, destination->shape);
    myl_rc_invariant(shape != NULL);
    if (shape->kind == MYL_RC_SHAPE_NONE) {
        memmove(destination->address, source->address, size);
        if (mode == MYL_RC_TAKE) memset(source->address, 0, size);
        return MYL_RC_OK;
    }
    if (!myl_rc_size_mul(size, 2, &bytes)) return MYL_RC_ALLOCATION_REFUSED;
    if (!bytes) return MYL_RC_OK;
    unsigned char local[256];
    unsigned char *storage = bytes <= sizeof local ? local : myl_rc_meta_alloc(heap, bytes);
    if (!storage) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_slot incoming = *destination;
    incoming.address = storage;
    myl_rc_status status = transfer(heap, &incoming, source, mode);
    if (status == MYL_RC_OK) {
        memcpy(storage + size, destination->address, size);
        memcpy(destination->address, storage, size);
        myl_rc_slot old = *destination;
        old.address = storage + size;
        myl_rc_value_drop(heap, &old);
    }
    if (storage != local) myl_rc_meta_free(heap, storage, bytes);
    return status;
}
static void *slot_payload(myl_native_heap *heap, const myl_rc_slot *slot) {
    myl_rc_invariant(slot && slot->address && myl_rc_shape_resolve(heap, slot->shape));
    myl_rc_invariant(slot->shape->kind == MYL_RC_SHAPE_POINTER && slot->shape->size == sizeof(void *));
    void *payload;
    memcpy(&payload, slot->address, sizeof payload);
    return payload;
}
myl_rc_status myl_rc_unique_owned(myl_native_heap *heap, myl_rc_slot *slot) {
    void *payload = slot_payload(heap, slot);
    if (myl_rc_unique(heap, payload)) return MYL_RC_OK;
    void *copy = NULL;
    myl_rc_status status = clone_payload(heap, payload, slot->region, &copy);
    if (status != MYL_RC_OK) return status;
    memcpy(slot->address, &copy, sizeof copy);
    myl_rc_owner_release(heap, payload);
    return MYL_RC_OK;
}
myl_rc_status myl_rc_unique_borrow(myl_native_heap *heap, const myl_rc_slot *slot,
                                   const myl_rc_scope *scope, myl_rc_edit *edit) {
    myl_rc_invariant(edit && !edit->payload && !edit->owned);
    myl_rc_invariant(!scope || (scope->active && scope->heap == heap));
    void *payload = slot_payload(heap, slot);
    if (myl_rc_unique(heap, payload)) { edit->payload = payload; return MYL_RC_OK; }
    void *copy = NULL;
    myl_rc_status status = clone_payload(heap, payload, slot->region, &copy);
    if (status != MYL_RC_OK) return status;
    edit->payload = copy;
    edit->owned = 1;
    return MYL_RC_OK;
}
void myl_rc_edit_abort(myl_native_heap *heap, myl_rc_edit *edit) {
    myl_rc_invariant(edit != NULL);
    void *payload = edit->payload;
    unsigned owned = edit->owned;
    *edit = (myl_rc_edit){0};
    if (owned) myl_rc_construction_abort(heap, payload);
}
void myl_rc_edit_commit(myl_native_heap *heap, myl_rc_slot *slot, myl_rc_edit *edit) {
    myl_rc_invariant(edit != NULL);
    void *old = slot_payload(heap, slot);
    if (edit->owned) {
        memcpy(slot->address, &edit->payload, sizeof edit->payload);
        *edit = (myl_rc_edit){0};
        myl_rc_owner_release(heap, old);
    } else {
        myl_rc_invariant(old == edit->payload);
        *edit = (myl_rc_edit){0};
    }
}
