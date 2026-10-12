/* Appended to each instrumented runtime only for native telemetry qualification.
 * These explicit counter sites model emitter records; this is not guest code. */
/* The normal guest emitter supplies this trampoline. No scheduler callback is
 * used in these native pthread controls; reaching one must fail visibly. */
myl_block *myl_core_task_call(void *run, myl_block *env) {
    (void)run;
    (void)env;
    abort();
}
static myl_count_fn control_function
    __attribute__((section("myl_count_fns"), used, aligned(8))) = {"native_counter_control", {0}};
static myl_count_site control_sites[3]
    __attribute__((section("myl_count_sites"), used, aligned(8))) = {
        {&control_function, "control", "native_control.c", "push", 1, 1, 9, 0, {0}},
        {&control_function, "control", "native_control.c", "copy", 2, 1, 4, 0, {0}},
        {&control_function, "control", "native_control.c", "direct drop", 3, 1, 2, 0, {0}},
    };
static int64_t control_length;

static void *control_worker(void *unused) {
    (void)unused;
    myl_count_current = myl_count_function_local(&control_function);
    myl_count_current->c[MYL_COUNT_CALLS]++;
    myl_block *list = myl_core_list_new_slow(0, sizeof(int64_t));
    for (int64_t i = 0; i < control_length; i++) {
        myl_count_push_site = &control_sites[0];
        list = myl_core_list_grow(list, sizeof(int64_t));
        myl_count_push_site = NULL;
        ((int64_t *)block_data(list))[list->len++] = i;
        myl_count_site *push = myl_count_site_local(&control_sites[0]);
        push->c[0]++;
        push->c[1] += sizeof(int64_t);
    }
    myl_count_copy_site = &control_sites[1];
    myl_block *copy = myl_core_list_copy(list, sizeof(int64_t));
    if (copy == list || copy->len != control_length) abort();
    ((int64_t *)block_data(copy))[0] = -1;
    if (((int64_t *)block_data(list))[0] != 0) abort();
    int64_t sum = 0;
    for (int64_t i = 0; i < list->len; i++) sum += ((int64_t *)block_data(list))[i];
    if (sum != control_length * (control_length - 1) / 2) abort();
    myl_core_drop_owned(copy);
    myl_core_drop_owned(list);
    myl_count_site_local(&control_sites[2])->c[0] += 2;
    myl_count_current = NULL;
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    int workers = atoi(argv[1]);
    control_length = atoll(argv[2]);
    if (workers < 1 || workers > 8 || control_length < 1) return 2;
    pthread_t threads[8];
    for (int i = 0; i < workers; i++) if (pthread_create(&threads[i], NULL, control_worker, NULL)) abort();
    for (int i = 0; i < workers; i++) if (pthread_join(threads[i], NULL)) abort();
    /* Native workers have joined before aggregation; no task work is pending. */
    myl_count_dump();
    puts("native counter control passed");
    return 0;
}
