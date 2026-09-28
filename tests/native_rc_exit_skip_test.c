/* RC-EXIT-SKIP-1 in a production RC runtime (no counting): the entry asks the
 * runtime before releasing its owners, and the runtime answers yes only for a
 * final run with no registered handle open. Each mode is its own process,
 * because "final" is a process-wide claim. `retire` is hooked to count how many
 * objects the guest actually released. */
#include "qbe_runtime.h"
#include "native_rc_alloc.h"
#include "native_rc_collections.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <string.h>
const myl_rc_module myl_rc_generated_module = {.abi = MYL_RC_ABI_VERSION};
static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static void (*retire_object)(myl_native_heap *, void *);
static unsigned retired, asked, dropped;
static int with_handle;
static void counting_retire(myl_native_heap *heap, void *payload) {
    ++retired;
    retire_object(heap, payload);
}
static uint64_t entry(void *context) {
    MylQbeContext *ctx = context;
    assert(myl_rc_native_shape(&ctx->heap, &pointer));
    retire_object = ctx->heap.rc->allocator.hooks.retire;
    ctx->heap.rc->allocator.hooks.retire = counting_retire;
    myl_native_list *list = myl_native_list_new(&ctx->heap, &number, 1);
    assert(list);
    uint32_t initialized = 1;
    MylQbeRcSlot slot = {&pointer, &list, &initialized, MYL_QBE_RC_COUNTED};
    /* An open registered handle is what a live resource looks like to the guard. */
    if (with_handle) ctx->resource_live[0] = 1;
    /* The generated exit: ask once, and keep the drop only when told to. */
    asked = (unsigned)myl_qbe_exit_skip(ctx);
    if (!asked) myl_qbe_rc_slot_drop(ctx, &slot);
    ctx->resource_live[0] = 0;
    dropped = retired;
    return 7;
}
int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "";
    with_handle = !strcmp(mode, "final-handle");
    int final = !strcmp(mode, "final") || with_handle;
    if (final) myl_qbe_exit_without_sweep();
    MylQbeResult result = {0};
    int failed = mylang_qbe_execute_config(entry, 100000, 64, 0, NULL, NULL, &result);
    assert(!failed);
    assert(!result.code && result.value == 7);
    /* A final run with no handle keeps its owner and skips every release to the
     * end, including the runner's own; a run that may go on, or has a handle
     * open, releases the owner in the frame as ever. */
    assert(asked == (unsigned)(final && !with_handle));
    assert(asked ? dropped == 0 && retired == 0 : dropped >= 1 && retired >= dropped);
    return 0;
}
