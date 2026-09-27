#include "qbe_runtime.h"
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
#include "native_rc_internal.h"
#include "native_rc_values.h"
#include "native_arena.h"
#include "native_dictionary.h"
#include <string.h>
_Static_assert(sizeof(MylQbeRcSlot) == MYL_QBE_RC_SLOT_BYTES, "RC slot journal size");
_Static_assert(offsetof(MylQbeRcSlot, type) == MYL_QBE_RC_SLOT_TYPE_OFFSET, "RC slot type");
_Static_assert(offsetof(MylQbeRcSlot, address) == MYL_QBE_RC_SLOT_ADDRESS_OFFSET, "RC slot address");
_Static_assert(offsetof(MylQbeRcSlot, initialized) == MYL_QBE_RC_SLOT_INITIALIZED_OFFSET, "RC slot guard");
_Static_assert(offsetof(MylQbeRcSlot, flags) == MYL_QBE_RC_SLOT_FLAGS_OFFSET, "RC slot flags");
_Static_assert(sizeof(MylQbeRcFrame) == MYL_QBE_RC_FRAME_BYTES, "RC frame journal size");
_Static_assert(offsetof(MylQbeRcFrame, previous) == MYL_QBE_RC_FRAME_PREVIOUS_OFFSET, "RC frame previous");
_Static_assert(offsetof(MylQbeRcFrame, entries) == MYL_QBE_RC_FRAME_ENTRIES_OFFSET, "RC frame entries");
_Static_assert(offsetof(MylQbeRcFrame, count) == MYL_QBE_RC_FRAME_COUNT_OFFSET, "RC frame count");
_Static_assert(offsetof(MylQbeRcFrame, scope_checkpoint) == MYL_QBE_RC_FRAME_SCOPE_OFFSET, "RC frame scope");
/* The compiler emits exactly one externally visible module in runtime_data.
 * A foreign/old artifact cannot enter RC with missing ownership metadata. */
extern const myl_rc_module myl_rc_generated_module __attribute__((weak));
int myl_qbe_rc_status(void *context, myl_rc_status status) {
    if (status == MYL_RC_OK) return 1;
    MylQbeContext *ctx = context;
    const char *code = status == MYL_RC_ALLOCATION_REFUSED && ctx->heap.exhausted ?
        "R_MEMORY_BUDGET" : myl_rc_status_code(status);
    myl_qbe_fail(context, code);
    return 0;
}
int myl_qbe_rc_register(void *context, const myl_rc_module *module) {
    MylQbeContext *ctx = context;
    if (!ctx->heap.rc || !module || module->abi != MYL_RC_ABI_VERSION) { myl_qbe_fail(context, "R_INTERNAL"); return 0; }
    return myl_qbe_rc_status(context, myl_rc_module_register(&ctx->heap, module));
}
int myl_qbe_rc_initialize(void *context) {
    MylQbeContext *ctx = context;
    if (!ctx->heap.rc) return myl_qbe_rc_status(context, MYL_RC_ALLOCATION_REFUSED);
    return myl_qbe_rc_register(context, &myl_rc_generated_module);
}
void myl_qbe_rc_frame_enter(void *context, MylQbeRcFrame *frame, MylQbeRcSlot *entries, size_t count) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(ctx && ctx->heap.rc && frame && (!count || entries));
    *frame = (MylQbeRcFrame){.previous = ctx->rc_frames, .entries = entries, .count = count,
        .scope_checkpoint = myl_rc_scope_current(&ctx->heap)};
    ctx->rc_frames = frame;
}
void myl_qbe_rc_frame_leave(void *context, MylQbeRcFrame *frame) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(ctx && frame && ctx->rc_frames == frame);
    myl_rc_invariant(myl_rc_scope_current(&ctx->heap) == frame->scope_checkpoint);
    ctx->rc_frames = frame->previous;
    *frame = (MylQbeRcFrame){0};
}
void myl_qbe_rc_slot_drop(void *context, MylQbeRcSlot *slot) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(slot && slot->initialized);
    if (!*slot->initialized) return;
    *slot->initialized = 0;
    myl_rc_invariant(slot->type && slot->address && !(slot->flags & ~31u));
    if (slot->flags & MYL_QBE_RC_LOAN) {
        myl_rc_invariant(slot->flags == MYL_QBE_RC_LOAN);
        myl_rc_native_unloan(&ctx->heap, slot->type, slot->address);
        return;
    }
    if (slot->flags & MYL_QBE_RC_HOLD_POINTER) {
        myl_rc_invariant(slot->flags == MYL_QBE_RC_HOLD_POINTER && slot->type->size == sizeof(void *));
        myl_rc_hold hold;
        memcpy(&hold.payload, slot->address, sizeof hold.payload);
        memset(slot->address, 0, sizeof hold.payload);
        myl_rc_hold_release(&ctx->heap, &hold);
        return;
    }
    if (slot->flags & MYL_QBE_RC_CONSTRUCTION) {
        myl_rc_invariant(slot->flags == MYL_QBE_RC_CONSTRUCTION && slot->type->size == sizeof(void *));
        void *payload;
        memcpy(&payload, slot->address, sizeof payload);
        memset(slot->address, 0, sizeof payload);
        myl_rc_construction_abort(&ctx->heap, payload);
        return;
    }
    if (slot->flags & MYL_QBE_RC_UNIQUE_DROP) myl_native_owned_drop(&ctx->heap, slot->type, slot->address);
    if (slot->flags & MYL_QBE_RC_COUNTED) myl_rc_native_drop(&ctx->heap, slot->type, slot->address);
}
void myl_qbe_rc_frame_cleanup(void *context, MylQbeRcFrame *frame) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(ctx && frame && ctx->rc_frames == frame);
    myl_rc_scope_unwind(&ctx->heap, frame->scope_checkpoint);
    for (size_t i = frame->count; i; --i) {
        MylQbeRcSlot *slot = &frame->entries[i - 1];
        /* Most normal exits have transferred these tokens already. Preserve
         * invalid-metadata diagnosis, but skip the full helper for empty slots. */
        if (!slot->initialized || *slot->initialized) myl_qbe_rc_slot_drop(ctx, slot);
    }
}
void myl_qbe_rc_unwind_to(void *context, MylQbeRcFrame *checkpoint) {
    MylQbeContext *ctx = context;
    while (ctx->rc_frames != checkpoint) {
        MylQbeRcFrame *frame = ctx->rc_frames;
        myl_rc_invariant(frame != NULL);
        myl_rc_scope_unwind(&ctx->heap, frame->scope_checkpoint);
        /* Unlink first: a resource callback may reenter guest execution. */
        ctx->rc_frames = frame->previous;
        for (size_t i = frame->count; i; --i) myl_qbe_rc_slot_drop(ctx, &frame->entries[i - 1]);
        *frame = (MylQbeRcFrame){0};
    }
}
void myl_qbe_rc_unwind(void *context) {
    MylQbeContext *ctx = context;
    myl_qbe_rc_unwind_to(ctx, NULL);
    myl_rc_scope_unwind(&ctx->heap, NULL);
}
void myl_qbe_rc_finish(void *context) {
    MylQbeContext *ctx = context;
    if (!ctx->heap.rc) return;
    myl_qbe_rc_unwind(ctx);
    myl_native_arena_release(&ctx->heap, 0);
    ctx->heap.region_depth = 0;
    for (size_t i = 0; i < 128; ++i) {
        void *text = ctx->heap.text_scalars[i];
        ctx->heap.text_scalars[i] = NULL;
        myl_rc_owner_release(&ctx->heap, text);
    }
}
void myl_qbe_rc_arena_prepare(void *context, MylQbeRcFrame *frame, size_t watermark) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(ctx->rc_frames == frame && watermark <= frame->count && ctx->heap.region_depth);
    myl_rc_scopes_close_region(&ctx->heap, ctx->heap.region_depth);
    for (size_t i = frame->count; i > watermark; --i)
        myl_qbe_rc_slot_drop(ctx, &frame->entries[i - 1]);
}
/* Detachment replaces an existing value, so it must not shorten that value's
 * allocation lifetime merely because the mutation runs inside a younger arena.
 * An enclosing object can impose a stricter bound; ordinary transfers still
 * choose their destination region explicitly. */
static unsigned unique_region(void *address, void *container) {
    void *payload;
    memcpy(&payload, address, sizeof payload);
    unsigned region = payload ? myl_native_header_region(payload) : 0;
    if (container && myl_native_header_region(container) < region)
        region = myl_native_header_region(container);
    return region;
}
/* An already unique payload needs no slot, region or edit: both the owned and
 * the borrowed protocol leave it in place. Only that answer is recorded here;
 * every other case takes the counting general path below. */
static int unique_in_place(MylQbeContext *ctx, const myl_native_type *type, const void *address) {
    myl_rc_checked(myl_rc_binding_find(&ctx->heap, type) &&
        myl_rc_binding_find(&ctx->heap, type)->descriptor.shape->kind == MYL_RC_SHAPE_POINTER);
    (void)type;
    void *payload;
    memcpy(&payload, address, sizeof payload);
    if (!myl_rc_unique_payload(payload)) return 0;
    MYL_RC_STAT(&ctx->heap, MYL_RC_STAT_UNIQUE_CHECK);
    return 1;
}
int myl_qbe_rc_unique_local(void *context, const myl_native_type *type, void *address, uint32_t *owned) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(owned != NULL);
    if (unique_in_place(ctx, type, address)) return 1;
    const myl_rc_binding *binding = myl_rc_binding_find(&ctx->heap, type);
    myl_rc_invariant(binding && binding->descriptor.shape->kind == MYL_RC_SHAPE_POINTER);
    const myl_rc_descriptor *descriptor = &binding->descriptor;
    myl_rc_slot slot = {.shape = descriptor->shape, .address = address, .region = unique_region(address, NULL)};
    if (*owned) return myl_qbe_rc_status(ctx, myl_rc_unique_owned(&ctx->heap, &slot));
    myl_rc_edit edit = {0};
    myl_rc_status status = myl_rc_unique_borrow(&ctx->heap, &slot, NULL, &edit);
    if (status == MYL_RC_OK && edit.owned) {
        memcpy(address, &edit.payload, sizeof edit.payload);
        *owned = 1;
    }
    return myl_qbe_rc_status(ctx, status);
}
int myl_qbe_rc_unique_field(void *context, const myl_native_type *type, void *address, void *container) {
    MylQbeContext *ctx = context;
    if (unique_in_place(ctx, type, address)) return 1;
    const myl_rc_binding *binding = myl_rc_binding_find(&ctx->heap, type);
    myl_rc_invariant(binding && binding->descriptor.shape->kind == MYL_RC_SHAPE_POINTER);
    myl_rc_slot slot = {.shape = binding->descriptor.shape, .address = address, .container = container,
        .region = unique_region(address, container)};
    return myl_qbe_rc_status(ctx, myl_rc_unique_owned(&ctx->heap, &slot));
}
int myl_qbe_rc_unique_elements(void *context, const myl_native_type *type, void *payload) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(type && type->kind == MYL_NATIVE_POINTER && type->collection_kind == 1 && type->element);
    const myl_native_type *element = type->element;
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_of(&ctx->heap, element);
    myl_rc_invariant(element->kind == MYL_NATIVE_POINTER && element->size == sizeof(void *) &&
        descriptor && descriptor->shape->kind == MYL_RC_SHAPE_POINTER);
    if (!payload) return 1;
    myl_rc_invariant(myl_native_list_header(payload) && myl_rc_unique(&ctx->heap, payload));
    myl_native_list *list = payload;
    descriptor = myl_rc_descriptor_of(&ctx->heap, list->element);
    myl_rc_invariant(list->element->kind == MYL_NATIVE_POINTER && list->element->size == sizeof(void *) &&
        descriptor && descriptor->shape->kind == MYL_RC_SHAPE_POINTER);
    myl_rc_slot slot = {.shape = descriptor->shape, .container = list, .region = myl_native_header_region(list)};
    for (size_t i = 0; i < list->length; ++i) {
        slot.address = (unsigned char *)list->storage + i * sizeof(void *);
        slot.region = unique_region(slot.address, list);
        myl_rc_status status = myl_rc_unique_owned(&ctx->heap, &slot);
        if (status != MYL_RC_OK) return myl_qbe_rc_status(ctx, status);
    }
    return 1;
}
static int unique_held(void *context, const myl_native_type *type, void *address, void *container, unsigned box) {
    static const myl_rc_shape held = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_HOLD_POINTER};
    static const myl_rc_shape *const shapes[] = {&held};
    static const myl_rc_module module = {.abi = MYL_RC_ABI_VERSION, .shapes = shapes, .shape_count = 1};
    MylQbeContext *ctx = context;
    myl_rc_invariant(type && type->size == sizeof(void *) && type->kind == MYL_NATIVE_POINTER);
    myl_rc_status status = myl_rc_module_register(&ctx->heap, &module);
    if (status != MYL_RC_OK) return myl_qbe_rc_status(ctx, status);
    myl_rc_slot slot = {.shape = &held, .address = address, .container = container,
        .region = unique_region(address, container)};
    if (box) myl_rc_invariant(type->collection_kind == 5 && type->element);
    return myl_qbe_rc_status(ctx, box ? myl_rc_box_detach_held(&ctx->heap, &slot) : myl_rc_unique_held(&ctx->heap, &slot));
}
int myl_qbe_rc_unique_held(void *context, const myl_native_type *type, void *address, void *container) {
    return unique_held(context,type,address,container,0);
}
int myl_qbe_rc_box_detach_held(void *context, const myl_native_type *type, void *address, void *container) {
    return unique_held(context,type,address,container,1);
}
int myl_qbe_rc_rebox_local(void *context, const myl_native_type *type, void *address, const void *body, uint32_t *owned) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(type && type->collection_kind == 5 && type->element && address && body && owned);
    void *old;
    memcpy(&old, address, sizeof old);
    myl_rc_invariant(old != NULL);
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_of(&ctx->heap, type->element);
    myl_rc_invariant(descriptor && !descriptor->finalize && !descriptor->edges);
    myl_rc_alloc_request request = {.element = type->element, .count = 1, .region = myl_native_header_region(old)};
    void *replacement = NULL;
    myl_rc_status status = myl_rc_new(&ctx->heap, &request, &replacement);
    if (status == MYL_RC_OK) {
        myl_rc_slot destination = {.shape = descriptor->shape, .address = replacement, .region = request.region};
        myl_rc_slot source = {.shape = descriptor->shape, .address = (void *)body};
        // This body was already evaluated and detached. Publishing its box is
        // physical retention: another pin clone would strand the live receiver.
        status = myl_rc_value_retain_many(&ctx->heap, &destination, &source, 1);
    }
    if (status != MYL_RC_OK) {
        myl_rc_construction_abort(&ctx->heap, replacement);
        return myl_qbe_rc_status(ctx, status);
    }
    uint32_t previous = *owned;
    memcpy(address, &replacement, sizeof replacement);
    *owned = 1;
    if (previous) myl_rc_owner_release(&ctx->heap, old);
    return 1;
}
_Static_assert(sizeof(myl_rc_scope) == MYL_QBE_RC_SCOPE_BYTES, "RC scope size");
_Static_assert(sizeof(MylQbeRcPath) == MYL_QBE_RC_PATH_BYTES, "RC native projection size");
_Static_assert(sizeof(MylQbeRcPlace) == MYL_QBE_RC_PLACE_BYTES, "RC native place size");
void myl_qbe_rc_scope_begin(void *context, myl_rc_scope *scope) {
    myl_rc_scope_begin(&((MylQbeContext *)context)->heap, scope);
}
void myl_qbe_rc_scope_end(void *context, myl_rc_scope *scope) {
    myl_rc_invariant(scope && (!scope->active || scope->heap == &((MylQbeContext *)context)->heap));
    myl_rc_scope_end(scope);
}
static myl_rc_status capture_backing(myl_rc_scope *scope, void *payload) {
    if (myl_native_list_header(payload)) return myl_rc_scope_hold(scope, ((myl_native_list *)payload)->storage);
    if (!myl_native_dictionary_header(payload)) return MYL_RC_OK;
    myl_native_dictionary *dictionary = payload;
    myl_rc_status status = myl_rc_scope_hold(scope, dictionary->entries);
    if (status == MYL_RC_OK && dictionary->entries) status = myl_rc_scope_hold(scope, dictionary->entries->storage);
    if (status == MYL_RC_OK) status = myl_rc_scope_hold(scope, dictionary->index.slots);
    return status;
}
int myl_qbe_rc_scope_pin(void *context, myl_rc_scope *scope, void *payload) {
    void *boundary = scope->journal;
    myl_rc_status status = myl_rc_scope_pin(scope, payload);
    if (status == MYL_RC_OK) status = myl_rc_scope_extend(scope, boundary, capture_backing);
    return myl_qbe_rc_status(context, status);
}
int myl_qbe_rc_scope_hold(void *context, myl_rc_scope *scope, void *payload) {
    void *boundary = scope->journal;
    myl_rc_status status = myl_rc_scope_hold(scope, payload);
    if (status == MYL_RC_OK) status = myl_rc_scope_extend(scope, boundary, capture_backing);
    return myl_qbe_rc_status(context, status);
}
static const myl_rc_shape scope_pointer = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_POINTER};
static const myl_rc_shape *const scope_shapes[] = {&scope_pointer};
static const myl_rc_module scope_module = {.abi = MYL_RC_ABI_VERSION, .shapes = scope_shapes, .shape_count = 1};
static int scope_prepare(void *context, myl_rc_scope *scope, const MylQbeRcPlace *request, unsigned loan) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(request && (!request->count || request->path));
    if (!request->address) return 1;
    size_t bytes;
    if (!myl_rc_size_mul(request->count, sizeof(myl_rc_projection), &bytes)) return myl_qbe_rc_status(ctx, MYL_RC_ALLOCATION_REFUSED);
    myl_rc_projection local[8], *path = bytes <= sizeof local ? local : myl_rc_meta_alloc(&ctx->heap, bytes);
    if (!path) return myl_qbe_rc_status(ctx, MYL_RC_ALLOCATION_REFUSED);
    for (size_t i = 0; i < request->count; ++i) {
        const myl_rc_descriptor *descriptor = myl_rc_descriptor_of(&ctx->heap, request->path[i].type);
        myl_rc_invariant(descriptor != NULL);
        path[i] = (myl_rc_projection){.shape=descriptor->shape,.offset=request->path[i].offset,
            .immutable_box=request->path[i].type->collection_kind==5};
    }
    myl_rc_status status = request->count ? MYL_RC_OK : myl_rc_module_register(&ctx->heap, &scope_module);
    if (status == MYL_RC_OK) {
        void *boundary = scope->journal;
        myl_rc_place place = {.receiver = {.shape = request->count ? path[0].shape : &scope_pointer,
            .address = request->address, .container = request->container,
            .region = request->container ? myl_native_header_region(request->container) : ctx->heap.region_depth},
            .path = path, .count = request->count};
        status = loan ? myl_rc_scope_prepare_loan(scope, &place) : myl_rc_scope_prepare(scope, &place);
        if (status == MYL_RC_OK) status = myl_rc_scope_extend(scope, boundary, capture_backing);
    }
    if (path != local) myl_rc_meta_free(&ctx->heap, path, bytes);
    return myl_qbe_rc_status(ctx, status);
}
int myl_qbe_rc_scope_prepare(void *context, myl_rc_scope *scope, const MylQbeRcPlace *request) {
    return scope_prepare(context,scope,request,0);
}
int myl_qbe_rc_scope_prepare_loan(void *context, myl_rc_scope *scope, const MylQbeRcPlace *request) {
    return scope_prepare(context,scope,request,1);
}
#endif

#if defined(MYL_NATIVE_RC)
int myl_qbe_rc_box_detach(void *context, const myl_native_type *type, void *address, void *container) {
    MylQbeContext *ctx=context;
    myl_rc_invariant(type && type->collection_kind==5 && type->element);
    const myl_rc_shape *shape=myl_rc_native_shape(&ctx->heap,type);
    if (!shape) return myl_qbe_rc_status(ctx,myl_rc_take_failure(&ctx->heap));
    myl_rc_slot slot={.shape=shape,.address=address,.container=container,
        .region=container?myl_native_header_region(container):ctx->heap.region_depth};
    return myl_qbe_rc_status(ctx,myl_rc_box_detach_owned(&ctx->heap,&slot));
}
#endif
