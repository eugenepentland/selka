#include "native_rc_internal.h"
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(uintptr_t) == 8, "RC-v1 targets 64-bit native artifacts");
_Static_assert(sizeof(myl_native_object) == 16, "GC/arena/literal common prefix remains 16 bytes");
_Static_assert(sizeof(myl_rc_object) == MYL_RC_PREFIX_BYTES, "RC prefix is 32 bytes");
_Static_assert(offsetof(myl_rc_object, owners) == 0, "owners at payload minus 32");
_Static_assert(offsetof(myl_rc_object, holds) == 8, "holds at payload minus 24");
_Static_assert(offsetof(myl_rc_object, common.mark) == 16, "mark at payload minus 16");
_Static_assert(offsetof(myl_rc_object, common.element) == 24, "descriptor at payload minus 8");
_Static_assert(sizeof(myl_rc_object) % _Alignof(max_align_t) == 0, "RC payload preserves alignment");
_Static_assert(offsetof(myl_native_heap, inline_windows) == MYL_NATIVE_HEAP_INLINE_OFFSET, "GC inline window unchanged");
_Static_assert(offsetof(myl_native_heap, arena_window) == MYL_NATIVE_HEAP_ARENA_OFFSET, "arena inline window unchanged");

void myl_rc_invariant_failed(void) {
    abort();
}
int myl_rc_meta_admit(myl_native_heap *heap, size_t bytes) {
    size_t total;
    myl_rc_invariant(heap && heap->rc && bytes);
    if (!myl_rc_size_add(heap->bytes, bytes, &total) || (heap->limit && total > heap->limit)) {
        heap->exhausted = 1;
        return 0;
    }
    return 1;
}
void myl_rc_meta_charge(myl_native_heap *heap, size_t bytes) {
    heap->bytes += bytes;
    heap->rc->metadata.bytes += bytes;
}
void myl_rc_meta_discharge(myl_native_heap *heap, size_t bytes) {
    myl_rc_invariant(heap->bytes >= bytes && heap->rc->metadata.bytes >= bytes);
    heap->bytes -= bytes;
    heap->rc->metadata.bytes -= bytes;
}
void *myl_rc_meta_alloc(myl_native_heap *heap, size_t bytes) {
    if (!myl_rc_meta_admit(heap, bytes)) return NULL;
    void *memory = calloc(1, bytes);
    if (!memory) return NULL;
    myl_rc_meta_charge(heap, bytes);
    return memory;
}
void myl_rc_meta_free(myl_native_heap *heap, void *memory, size_t bytes) {
    if (!memory) return;
    myl_rc_meta_discharge(heap, bytes);
    free(memory);
}
const char *myl_rc_status_code(myl_rc_status status) {
    switch (status) {
        case MYL_RC_OK: return NULL;
        case MYL_RC_ALLOCATION_REFUSED: return "OutOfMemory";
        case MYL_RC_COUNT_LIMIT: return MYL_RC_COUNT_LIMIT_CODE;
        case MYL_RC_REGION_ERROR: return "R_ARENA_ESCAPE";
    }
    abort();
}
int myl_rc_enabled(const myl_native_heap *heap) { return heap && heap->rc; }
void myl_rc_record_failure(myl_native_heap *heap, myl_rc_status status) {
    myl_rc_invariant(heap && heap->rc);
    if (heap->rc->failure == MYL_RC_OK) heap->rc->failure = status;
}
myl_rc_status myl_rc_take_failure(myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc);
    myl_rc_status status = heap->rc->failure;
    heap->rc->failure = MYL_RC_OK;
    return status;
}
myl_rc_status myl_rc_heap_init(myl_native_heap *heap, const myl_rc_allocator *allocator, void *context) {
    size_t total;
    myl_rc_invariant(heap && !heap->rc && allocator && allocator->allocate && allocator->retire);
    if (!myl_rc_size_add(heap->bytes, sizeof(myl_rc_state), &total) || (heap->limit && total > heap->limit)) {
        heap->exhausted = 1;
        return MYL_RC_ALLOCATION_REFUSED;
    }
    myl_rc_state *state = calloc(1, sizeof *state);
    if (!state) return MYL_RC_ALLOCATION_REFUSED;
    state->allocator.hooks = *allocator;
    state->allocator.context = context;
    state->metadata.bytes = sizeof *state;
    myl_rc_metadata_init(state);
    heap->bytes = total;
    heap->rc = state;
    return MYL_RC_OK;
}
void *myl_rc_allocator_context(const myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc);
    return heap->rc->allocator.context;
}
size_t myl_rc_reserved_depth(const myl_native_heap *heap) { return heap->rc ? heap->rc->walk.capacity : 0; }
size_t myl_rc_metadata_bytes(const myl_native_heap *heap) { return heap->rc ? heap->rc->metadata.bytes : 0; }
void myl_rc_heap_destroy(myl_native_heap *heap) {
    if (!heap->rc) return;
    myl_rc_drain(heap);
    myl_rc_state *state = heap->rc;
    myl_rc_invariant(!state->scopes && !state->walk.depth && !state->dead.active);
    myl_rc_scope_spares_release(heap);
    if (state->allocator.hooks.destroy) state->allocator.hooks.destroy(heap);
    while (state->metadata.batches) {
        myl_rc_batch *batch = state->metadata.batches;
        state->metadata.batches = batch->next;
        myl_rc_meta_free(heap, batch, batch->bytes);
    }
    myl_rc_meta_free(heap, state->walk.frames, state->walk.capacity * sizeof(myl_rc_frame));
    myl_rc_metadata_release(heap);
    myl_rc_invariant(state->metadata.bytes == sizeof *state);
    heap->bytes -= sizeof *state;
    free(state);
    heap->rc = NULL;
}
void myl_rc_heap_teardown(myl_native_heap *heap) {
    if (!heap->rc) return;
    myl_rc_state *state = heap->rc;
    myl_rc_scopes_abandon(heap);
    state->dead.head = NULL;
    state->dead.active = 0;
    state->walk.depth = 0;
    state->failure = MYL_RC_OK;
    myl_rc_invariant(state->allocator.hooks.teardown != NULL);
    state->allocator.hooks.teardown(heap);
}
myl_rc_status myl_rc_new(myl_native_heap *heap, const myl_rc_alloc_request *request, void **out) {
    size_t bytes;
    myl_rc_invariant(heap && heap->rc && request && out);
    *out = NULL;
    myl_rc_invariant(request->element != NULL);
    myl_rc_checked(myl_rc_binding_find(heap, request->element) != NULL);
    if (!myl_rc_size_mul(request->element->size, request->count, &bytes) ||
        !myl_rc_size_add(bytes, request->region ? sizeof(myl_native_object) : MYL_RC_PREFIX_BYTES, &bytes) ||
        request->count > (request->region ? MYL_NATIVE_ARENA_COUNT_MAX : MYL_NATIVE_OBJECT_COUNT_MAX))
        return MYL_RC_ALLOCATION_REFUSED;
    if (request->region > heap->region_depth) return MYL_RC_REGION_ERROR;
    myl_rc_status status = heap->rc->allocator.hooks.allocate(heap, request, out);
    myl_rc_invariant(status == MYL_RC_OK ? *out != NULL : *out == NULL);
    MYL_RC_STAT_WHEN(heap, request->region ? MYL_RC_STAT_ARENA_ALLOCATE : MYL_RC_STAT_HEAP_ALLOCATE, status == MYL_RC_OK);
    return status;
}
void myl_rc_allocator_retire(myl_native_heap *heap, void *payload) {
    myl_rc_invariant(myl_rc_is_counted(payload));
    myl_rc_object *object = (myl_rc_object *)payload - 1;
    myl_rc_invariant((object->common.mark & MYL_RC_OBJECT_DYING) != 0);
    MYL_RC_STAT(heap, MYL_RC_STAT_RETIRE);
    heap->rc->allocator.hooks.retire(heap, payload);
}
int myl_rc_is_counted(const void *payload) { return myl_rc_counted(payload); }
static myl_rc_object *live_object(myl_native_heap *heap, void *payload) {
    myl_rc_invariant(heap && heap->rc);
    return myl_rc_live(payload);
}
myl_rc_status myl_rc_owner_acquire(myl_native_heap *heap, void *payload) {
    if (myl_rc_counted(payload)) myl_rc_invariant(heap && heap->rc);
    return myl_rc_owner_take(heap, payload);
}
/* An object whose admitted flat plan has no leaf has no edge, hook or
 * finalizer. Outside an active drain it retires at once instead of passing
 * through the queue; inside one (including finalizer reentry) it stays queued
 * behind its siblings, and the drain loop retires it without a walk. */
void myl_rc_dead_outside(myl_native_heap *heap, myl_rc_object *object) {
    const myl_rc_binding *binding = myl_rc_binding_find(heap, object->common.element);
    if (binding && !binding->flat.count) {
        myl_rc_retire(heap, object);
        return;
    }
    object->owners = (uintptr_t)heap->rc->dead.head;
    heap->rc->dead.head = object;
}
void myl_rc_enqueue(myl_native_heap *heap, myl_rc_object *object) {
    if (object->owners || object->holds) return;
    myl_rc_dies(heap, object);
}
void myl_rc_edge_release(myl_native_heap *heap, void *payload) {
    if (myl_rc_counted(payload)) myl_rc_invariant(heap && heap->rc);
    myl_rc_owner_drop(heap, payload);
}
void myl_rc_owner_release(myl_native_heap *heap, void *payload) {
    myl_rc_edge_release(heap, payload);
    if (heap && heap->rc) myl_rc_drain_pending(heap);
}
int myl_rc_unique(const myl_native_heap *heap, const void *payload) {
    MYL_RC_STAT(heap, MYL_RC_STAT_UNIQUE_CHECK);
    if (payload && !(((const myl_native_object *)payload - 1)->mark &
        (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_SHARED | MYL_NATIVE_OBJECT_ARENA)))
        myl_rc_invariant(heap && heap->rc);
    return myl_rc_unique_payload(payload);
}
myl_rc_status myl_rc_hold_acquire(myl_native_heap *heap, void *payload, myl_rc_hold *hold) {
    myl_rc_invariant(hold && !hold->payload);
    if (myl_rc_is_counted(payload)) {
        myl_rc_object *object = live_object(heap, payload);
        if (object->holds == MYL_RC_COUNT_MAX) { MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_LIMIT); return MYL_RC_COUNT_LIMIT; }
        ++object->holds;
        MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_ACQUIRE);
    }
    hold->payload = payload;
    return MYL_RC_OK;
}
void myl_rc_hold_edge_release(myl_native_heap *heap, void *payload) {
    if (myl_rc_counted(payload)) myl_rc_invariant(heap && heap->rc);
    myl_rc_hold_drop(heap, payload);
}
void myl_rc_hold_release(myl_native_heap *heap, myl_rc_hold *hold) {
    myl_rc_invariant(hold != NULL);
    void *payload = hold->payload;
    hold->payload = NULL;
    myl_rc_hold_edge_release(heap, payload);
    if (heap && heap->rc) myl_rc_drain_pending(heap);
}
myl_rc_status myl_rc_pin_acquire(myl_native_heap *heap, void *payload, myl_rc_pin *pin) {
    myl_rc_invariant(pin && !pin->hold.payload);
    myl_rc_status status = myl_rc_hold_acquire(heap, payload, &pin->hold);
    if (status != MYL_RC_OK) return status;
    pin->previous = 0;
    if (payload) {
        myl_native_object *common = (myl_native_object *)payload - 1;
        if (!(common->mark & MYL_NATIVE_OBJECT_IMMORTAL)) {
            pin->previous = common->mark & MYL_NATIVE_OBJECT_PINNED;
            common->mark |= MYL_NATIVE_OBJECT_PINNED;
        }
    }
    return MYL_RC_OK;
}
void myl_rc_pin_release(myl_native_heap *heap, myl_rc_pin *pin) {
    myl_rc_invariant(pin != NULL);
    if (pin->hold.payload) {
        myl_native_object *common = (myl_native_object *)pin->hold.payload - 1;
        if (!(common->mark & MYL_NATIVE_OBJECT_IMMORTAL))
            common->mark = (common->mark & ~MYL_NATIVE_OBJECT_PINNED) | pin->previous;
    }
    pin->previous = 0;
    myl_rc_hold_release(heap, &pin->hold);
}
