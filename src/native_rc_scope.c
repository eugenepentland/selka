#include "native_rc_internal.h"
#include <stdlib.h>
#include <string.h>

typedef struct scope_entry {
    struct scope_entry *previous;
    myl_rc_pin pin;
    unsigned pinned;
    /* RC-SCOPE-FAST-1: the one backing block (a list's storage) held right
     * after the payload, released right before it; NULL when there is none. */
    void *backing;
} scope_entry;
/* RC-SCOPE-SPARE-1: journal nodes are recycled through a bounded, uncharged
 * spare list (see myl_rc_spare), so a receiver statement in a loop reaches the
 * host allocator only on its first iteration. A recycled node is admitted and
 * charged like a fresh one, and giving one back discharges it.
 * RC-SCOPE-FAST-1: the receiver protocol (begin, pin with backing, end) is
 * forced inline into its public entries, so full LTO carries it into guest
 * code; only a fresh node, a full spare list and a failure leave the line.
 * The caller initializes every field of a taken node. */
#define SCOPE_HOT static inline __attribute__((always_inline))
static __attribute__((noinline, cold)) scope_entry *entry_fresh(myl_native_heap *heap) {
    return myl_rc_meta_alloc(heap, sizeof(scope_entry));
}
static __attribute__((noinline, cold)) void entry_release(myl_native_heap *heap, scope_entry *entry) {
    myl_rc_meta_free(heap, entry, sizeof *entry);
}
SCOPE_HOT scope_entry *entry_take(myl_native_heap *heap) {
    myl_rc_state *rc = heap->rc;
    myl_rc_spare *spare = rc->spare.entries;
    if (__builtin_expect(!spare, 0)) return entry_fresh(heap);
    if (__builtin_expect(!myl_rc_meta_fits(heap, sizeof(scope_entry)), 0)) { heap->exhausted = 1; return NULL; }
    rc->spare.entries = spare->next;
    --rc->spare.count;
    heap->bytes += sizeof(scope_entry);
    rc->metadata.bytes += sizeof(scope_entry);
    return (scope_entry *)spare;
}
SCOPE_HOT void entry_give(myl_native_heap *heap, scope_entry *entry) {
    myl_rc_state *rc = heap->rc;
    if (__builtin_expect(rc->spare.count == MYL_RC_SPARE_ENTRIES, 0)) { entry_release(heap, entry); return; }
    myl_rc_invariant(heap->bytes >= sizeof *entry && rc->metadata.bytes >= sizeof *entry);
    heap->bytes -= sizeof *entry;
    rc->metadata.bytes -= sizeof *entry;
    myl_rc_spare *spare = (myl_rc_spare *)entry;
    spare->next = rc->spare.entries;
    rc->spare.entries = spare;
    ++rc->spare.count;
}
_Static_assert(sizeof(scope_entry) >= sizeof(myl_rc_spare), "spare link fits a journal node");
void myl_rc_scope_spares_release(myl_native_heap *heap) {
    while (heap->rc->spare.entries) {
        myl_rc_spare *spare = heap->rc->spare.entries;
        heap->rc->spare.entries = spare->next;
        free(spare);
    }
    heap->rc->spare.count = 0;
}
SCOPE_HOT void restore(scope_entry *entry) {
    if (!entry->pinned || !entry->pin.hold.payload) return;
    myl_native_object *header = (myl_native_object *)entry->pin.hold.payload - 1;
    if (!(header->mark & MYL_NATIVE_OBJECT_IMMORTAL))
        header->mark = (header->mark & ~MYL_NATIVE_OBJECT_PINNED) | entry->pin.previous;
}
/* A returned hold that was the last token: queue the death and drain it. */
static __attribute__((noinline, cold)) void hold_death(myl_native_heap *heap, myl_rc_object *object) {
    myl_rc_dies(heap, object);
    myl_rc_drain_pending(heap);
}
/* myl_rc_hold_drop followed by myl_rc_drain_pending, with the death out of line. */
SCOPE_HOT void hold_return(myl_native_heap *heap, void *payload) {
    if (myl_rc_counted(payload)) {
        myl_rc_object *object = (myl_rc_object *)payload - 1;
        myl_rc_invariant(object->holds != 0 && !(object->common.mark & MYL_RC_OBJECT_DYING));
        uintptr_t holds = --object->holds;
        MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_RELEASE);
        if (__builtin_expect(!holds && !object->owners, 0)) { hold_death(heap, object); return; }
    }
    myl_rc_drain_pending(heap);
}
/* Restore every bit before any final hold can run a destructor or callback. */
SCOPE_HOT void unwind(myl_rc_scope *scope, scope_entry *boundary) {
    scope_entry *head = scope->journal;
    if (head == boundary) return;
    for (scope_entry *entry = head; entry != boundary; entry = entry->previous) restore(entry);
    scope->journal = boundary;
    myl_native_heap *heap = scope->heap;
    do {
        scope_entry *entry = head;
        head = entry->previous;
        void *payload = entry->pin.hold.payload, *backing = entry->backing;
        entry_give(heap, entry);
        if (backing) hold_return(heap, backing);
        hold_return(heap, payload);
    } while (head != boundary);
}
inline __attribute__((always_inline)) void myl_rc_scope_begin(myl_native_heap *heap, myl_rc_scope *scope) {
    myl_rc_invariant(heap && heap->rc && scope);
    *scope = (myl_rc_scope){.heap = heap, .previous = heap->rc->scopes, .active = 1, .region = heap->region_depth};
    heap->rc->scopes = scope;
}
/* One journal capture on an active scope of `heap`, which the caller checked. */
SCOPE_HOT myl_rc_status capture_in(myl_native_heap *heap, myl_rc_scope *scope, void *payload, unsigned pinned) {
    if (!payload) return MYL_RC_OK;
    myl_native_object *header = (myl_native_object *)payload - 1;
    uintptr_t mark = header->mark;
    if (mark & MYL_NATIVE_OBJECT_IMMORTAL) return MYL_RC_OK;
    /* An outer receiver may span younger callbacks, but it cannot acquire a
     * hold that pretends to extend a younger arena's chunk lifetime. */
    if (__builtin_expect(myl_native_header_region(payload) > scope->region, 0)) return MYL_RC_REGION_ERROR;
    scope_entry *entry = entry_take(heap);
    if (__builtin_expect(!entry, 0)) return MYL_RC_ALLOCATION_REFUSED;
    /* The pin/hold acquisition of myl_rc_pin_acquire/myl_rc_hold_acquire;
     * immortal payloads were excluded above, so only an arena one is uncounted. */
    if (!(mark & MYL_NATIVE_OBJECT_ARENA)) {
        myl_rc_object *object = myl_rc_live(payload);
        if (__builtin_expect(object->holds == MYL_RC_COUNT_MAX, 0)) {
            MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_LIMIT);
            entry_give(heap, entry);
            return MYL_RC_COUNT_LIMIT;
        }
        ++object->holds;
        MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_ACQUIRE);
    }
    entry->pin.hold.payload = payload;
    entry->backing = NULL;
    entry->pin.previous = pinned ? mark & MYL_NATIVE_OBJECT_PINNED : 0;
    if (pinned) header->mark = mark | MYL_NATIVE_OBJECT_PINNED;
    entry->previous = scope->journal;
    entry->pinned = pinned;
    scope->journal = entry;
    return MYL_RC_OK;
}
SCOPE_HOT myl_rc_status capture(myl_rc_scope *scope, void *payload, unsigned pinned) {
    myl_rc_invariant(scope && scope->active && scope->heap && scope->heap->rc);
    return capture_in(scope->heap, scope, payload, pinned);
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
static __attribute__((noinline, cold)) myl_rc_status backing_refused(myl_rc_scope *scope, scope_entry *boundary, myl_rc_status status) {
    unwind(scope, boundary);
    return status;
}
/* A backing block's hold, recorded in the entry that captured its payload:
 * what capturing it as an entry of its own would acquire, and the same
 * refusals. A null or immortal block records nothing and an arena block needs
 * no count, exactly as their own entries would release nothing. */
SCOPE_HOT myl_rc_status backing_hold(myl_native_heap *heap, myl_rc_scope *scope, scope_entry *entry, void *block) {
    (void)heap;
    if (!block) return MYL_RC_OK;
    uintptr_t mark = ((const myl_native_object *)block - 1)->mark;
    if (mark & MYL_NATIVE_OBJECT_IMMORTAL) return MYL_RC_OK;
    if (__builtin_expect(myl_native_header_region(block) > scope->region, 0)) return MYL_RC_REGION_ERROR;
    if (mark & MYL_NATIVE_OBJECT_ARENA) return MYL_RC_OK;
    myl_rc_object *object = myl_rc_live(block);
    if (__builtin_expect(object->holds == MYL_RC_COUNT_MAX, 0)) {
        MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_LIMIT);
        return MYL_RC_COUNT_LIMIT;
    }
    ++object->holds;
    MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_ACQUIRE);
    entry->backing = block;
    return MYL_RC_OK;
}
inline __attribute__((always_inline)) myl_rc_status myl_rc_scope_capture_backed(myl_rc_scope *scope, void *payload, unsigned pinned,
                                                                         void *const *backing, size_t count) {
    myl_rc_invariant(scope && scope->active && scope->heap && scope->heap->rc);
    myl_native_heap *heap = scope->heap;
    scope_entry *boundary = scope->journal;
    myl_rc_status status = capture_in(heap, scope, payload, pinned);
    /* A null or immortal payload records nothing, so it has no backing to extend. */
    if (status != MYL_RC_OK || scope->journal == boundary) return status;
    if (count == 1) {
        status = backing_hold(heap, scope, scope->journal, backing[0]);
        if (__builtin_expect(status != MYL_RC_OK, 0)) return backing_refused(scope, boundary, status);
        return MYL_RC_OK;
    }
    for (size_t i = 0; i < count; ++i) {
        status = capture_in(heap, scope, backing[i], 0);
        if (__builtin_expect(status != MYL_RC_OK, 0)) return backing_refused(scope, boundary, status);
    }
    return MYL_RC_OK;
}
inline __attribute__((always_inline)) void myl_rc_scope_end(myl_rc_scope *scope) {
    myl_rc_invariant(scope != NULL);
    if (!scope->active) return;
    myl_native_heap *heap = scope->heap;
    myl_rc_invariant(heap && heap->rc && heap->rc->scopes == scope);
    heap->rc->scopes = scope->previous;
    scope->active = 0;
    scope->previous = NULL;
    unwind(scope, NULL);
    myl_rc_drain_pending(heap);
}
void myl_rc_scopes_abandon(myl_native_heap *heap) {
    if (!heap || !heap->rc) return;
    myl_rc_scope *scope = heap->rc->scopes;
    heap->rc->scopes = NULL;
    while (scope) {
        myl_rc_scope *previous = scope->previous;
        scope_entry *entry = scope->journal;
        while (entry) {
            scope_entry *older = entry->previous;
            entry_give(heap, entry);
            entry = older;
        }
        scope->journal = NULL;
        scope->previous = NULL;
        scope->active = 0;
        scope = previous;
    }
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
    unsigned region, loan;
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
static const myl_rc_shape loan_pointer = {.size=sizeof(void *),.kind=MYL_RC_SHAPE_HOLD_POINTER};
static const myl_rc_shape *const loan_shapes[] = {&loan_pointer};
static const myl_rc_module loan_module = {.abi=MYL_RC_ABI_VERSION,.shapes=loan_shapes,.shape_count=1};
static myl_rc_status prepare_leaf(myl_rc_scope *scope, prepare_frame *frame) {
    if (frame->shape->kind == MYL_RC_SHAPE_NONE) return MYL_RC_OK;
    myl_rc_invariant(frame->shape->kind == MYL_RC_SHAPE_POINTER || frame->shape->kind == MYL_RC_SHAPE_HOLD_POINTER);
    myl_rc_slot slot = {.shape = frame->loan ? &loan_pointer : frame->shape, .address = frame->address, .region = frame->region};
    void *payload;
    memcpy(&payload, frame->address, sizeof payload);
    /* Inline paths have no managed container from which to recover their
     * binding lifetime. Preserve each existing leaf's older allocation region
     * instead of moving it into the arena of the call that prepares it. */
    unsigned origin = payload ? myl_native_header_region(payload) : 0;
    if (origin < slot.region) slot.region = origin;
    myl_rc_status status = slot.shape->kind == MYL_RC_SHAPE_HOLD_POINTER ?
        myl_rc_unique_held(scope->heap, &slot) : myl_rc_unique_owned(scope->heap, &slot);
    if (status != MYL_RC_OK) return status;
    memcpy(&payload, frame->address, sizeof payload);
    return myl_rc_scope_pin(scope, payload);
}
static myl_rc_status prepare_box(myl_rc_scope *scope, prepare_frame *frame) {
    myl_rc_invariant(frame->shape->kind == MYL_RC_SHAPE_POINTER);
    myl_rc_slot slot = {.shape=frame->loan ? &loan_pointer : frame->shape,.address=frame->address,.region=frame->region};
    myl_rc_status status = frame->loan ? myl_rc_box_detach_held(scope->heap, &slot) : myl_rc_box_detach_owned(scope->heap, &slot);
    if (status != MYL_RC_OK) return status;
    void *payload;
    memcpy(&payload, frame->address, sizeof payload);
    return myl_rc_scope_pin(scope, payload);
}
static myl_rc_status prepare_path(myl_rc_scope *scope, const myl_rc_place *place, prepare_frame *frames, unsigned loan) {
    const myl_rc_shape *shape = myl_rc_shape_find(scope->heap, place->receiver.shape);
    myl_rc_invariant(shape != NULL);
    frames[0] = (prepare_frame){.shape = shape, .address = place->receiver.address, .region = place->receiver.region, .loan=loan};
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
        shape = myl_rc_shape_find(scope->heap, projection->shape);
        myl_rc_invariant(shape && shape->size == frame->shape->size);
        if (shape->kind == MYL_RC_SHAPE_ARRAY) {
            if (frame->cursor == shape->as.array.count) { --used; continue; }
            frames[used++] = (prepare_frame){.shape = shape->as.array.element,
                .address = frame->address + frame->cursor++ * shape->as.array.stride,
                .step = frame->step + 1, .region = frame->region, .loan=frame->loan};
            continue;
        }
        if (frame->cursor++) { --used; continue; }
        unsigned char *address = frame->address;
        unsigned region = frame->region;
        unsigned child_loan = frame->loan;
        if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) {
            myl_rc_status status = projection->immutable_box ? prepare_box(scope, frame) : prepare_leaf(scope, frame);
            if (status != MYL_RC_OK) return status;
            void *payload;
            memcpy(&payload, address, sizeof payload);
            if (!payload) { --used; continue; }
            const myl_native_object *header = (const myl_native_object *)payload - 1;
            const myl_rc_descriptor *descriptor = myl_rc_descriptor_of(scope->heap, header->element);
            myl_rc_invariant(descriptor != NULL);
            address = payload;
            region = myl_native_header_region(payload);
            shape = descriptor->shape;
            child_loan = 0;
        }
        const myl_rc_shape *child = member(shape, address, projection->offset);
        frames[used++] = (prepare_frame){.shape = child, .address = address + projection->offset,
            .step = frame->step + 1, .region = region, .loan=child_loan};
    }
    return MYL_RC_OK;
}
static myl_rc_status scope_prepare(myl_rc_scope *scope, const myl_rc_place *place, unsigned loan) {
    myl_rc_invariant(scope && scope->active && place && place->receiver.address && (!place->count || place->path));
    if (loan) {
        myl_rc_status status = myl_rc_module_register(scope->heap, &loan_module);
        if (status != MYL_RC_OK) return status;
    }
    size_t count, bytes;
    if (!myl_rc_size_add(place->count, 1, &count) || !myl_rc_size_mul(count, sizeof(prepare_frame), &bytes))
        return MYL_RC_ALLOCATION_REFUSED;
    /* A short path walks in local frames; only a long one charges metadata. */
    prepare_frame local[8];
    prepare_frame *frames = count <= sizeof local / sizeof *local ? local : myl_rc_meta_alloc(scope->heap, bytes);
    if (!frames) return MYL_RC_ALLOCATION_REFUSED;
    scope_entry *boundary = scope->journal;
    myl_rc_status status = myl_rc_scope_hold(scope, place->receiver.container);
    if (status == MYL_RC_OK) status = prepare_path(scope, place, frames, loan);
    if (frames != local) myl_rc_meta_free(scope->heap, frames, bytes);
    if (status != MYL_RC_OK) unwind(scope, boundary);
    return status;
}

myl_rc_status myl_rc_scope_prepare(myl_rc_scope *scope, const myl_rc_place *place) {
    return scope_prepare(scope, place, 0);
}
myl_rc_status myl_rc_scope_prepare_loan(myl_rc_scope *scope, const myl_rc_place *place) {
    return scope_prepare(scope, place, 1);
}
