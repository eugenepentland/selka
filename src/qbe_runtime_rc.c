#include "qbe_runtime.h"
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
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
#endif
