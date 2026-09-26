#include "qbe_runtime.h"
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
#include "native_rc_internal.h"
#include "native_rc_values.h"
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
    if (!ctx->heap.rc || !module) { myl_qbe_fail(context, "R_INTERNAL"); return 0; }
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
    myl_rc_invariant(slot->type && slot->address && !(slot->flags & ~3u));
    if (slot->flags & MYL_QBE_RC_UNIQUE_DROP) myl_native_owned_drop(&ctx->heap, slot->type, slot->address);
    if (slot->flags & MYL_QBE_RC_COUNTED) myl_rc_native_drop(&ctx->heap, slot->type, slot->address);
}
void myl_qbe_rc_frame_cleanup(void *context, MylQbeRcFrame *frame) {
    MylQbeContext *ctx = context;
    myl_rc_invariant(ctx && frame && ctx->rc_frames == frame);
    myl_rc_scope_unwind(&ctx->heap, frame->scope_checkpoint);
    for (size_t i = frame->count; i; --i) myl_qbe_rc_slot_drop(ctx, &frame->entries[i - 1]);
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
#endif
