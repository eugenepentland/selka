/* Included after the generated entry function. */
#ifdef MYLANG_EMBED
static atomic_flag entry_busy = ATOMIC_FLAG_INIT;
static int run_embedding(const char *name, const MylangScalar *arguments, size_t count,
    const MylangRunOptions *configuration, MylangRunResult *result, MylangScalar *scalar) {
    if (!result) return 2;
    *result = (MylangRunResult){0};
    if (atomic_flag_test_and_set_explicit(&entry_busy, memory_order_acquire)) {
        result->status = 2; result->code = "Busy"; return 2;
    }
    max_steps = configuration && configuration->max_steps ? configuration->max_steps : 10000000;
    max_frames = configuration && configuration->max_frames ? configuration->max_frames : 1024;
    providers = configuration && configuration->providers ? *configuration->providers : (MylangNativeProviders){0};
    steps = 0; site = 0; binding_call = 0; native_value = 0; native_bits = 0; native_type = "i64";
    nr = 0; next_region_identity = 2; next_pool_identity = 1;
    pool_owners = 0; pool_slots = 0; guest_capacity = 0;
    memset(regions, 0, sizeof regions);
    memset(active_regions, 0, sizeof active_regions);
    active_result = result;
    if (!setjmp(entry_escape)) {
        result->status = execute_entry(name, arguments, count);
        result->value = native_value;
    }
    if (scalar && result->status == 0) *scalar = (MylangScalar){native_type, native_bits};
    result->steps = steps;
    active_result = NULL;
    atomic_flag_clear_explicit(&entry_busy, memory_order_release);
    return result->status;
}
int mylang_native_run_v1(const MylangRunOptions *options, MylangRunResult *result) {
    return run_embedding(NULL, NULL, 0, options, result, NULL);
}
int mylang_native_call_v1(const char *name, const MylangScalar *arguments, size_t count,
    const MylangRunOptions *options, MylangCallResult *result) {
    if (!result) return 2;
    *result = (MylangCallResult){0};
    if (!name || (count && !arguments)) {
        result->execution.status = 2; result->execution.code = "InvalidArgument"; return 2;
    }
    return run_embedding(name, arguments, count, options, &result->execution, &result->value);
}
#endif
