#include "qbe_runtime.h"
#include "native_rc_collections.h"
#include <assert.h>
#include <string.h>
const myl_rc_module myl_rc_generated_module = {.abi = MYL_RC_ABI_VERSION};
static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static unsigned trapping;
static uint64_t entry(void *context) {
    MylQbeContext *ctx = context;
    assert(myl_rc_native_shape(&ctx->heap, &pointer));
    myl_native_list *leaf = myl_native_list_new(&ctx->heap, &number, 1);
    assert(leaf);
    uint32_t initialized = 1;
    MylQbeRcSlot slot = {&pointer, &leaf, &initialized, MYL_QBE_RC_COUNTED};
    assert(myl_native_region_begin(&ctx->heap));
    myl_native_list *outer = myl_native_list_new(&ctx->heap, &pointer, 1);
    assert(outer && myl_native_list_append(&ctx->heap, outer, &leaf));
    myl_rc_scope scope;
    myl_rc_scope_begin(&ctx->heap, &scope);
    assert(myl_rc_scope_pin(&scope, leaf) == MYL_RC_OK);
    /* A trap leaves the scope, the slot and the arena to heap teardown; a
     * normal return closes its scope and drops its slot statically. */
    if (trapping) myl_qbe_fail(ctx, "R_REFERENCE_COUNT_LIMIT");
    myl_rc_scope *const mine[] = {&scope};
    myl_qbe_rc_scopes_close(ctx, mine, 1);
    myl_qbe_rc_slot_drop(ctx, &slot);
    return 42;
}
int main(int argc, char **argv) {
    trapping = argc > 1 && !strcmp(argv[1], "trap");
    if (argc > 1 && !strcmp(argv[1], "fast")) myl_qbe_exit_without_sweep();
    MylQbeResult result = {0};
    int failed = mylang_qbe_execute_config(entry, 100000, 64, 0, NULL, NULL, &result);
    assert(failed == (int)trapping);
    assert(trapping ? result.code && !strcmp(result.code, "R_REFERENCE_COUNT_LIMIT") : !result.code && result.value == 42);
    return 0;
}
