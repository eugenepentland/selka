/* TASK-SCHEDULER-1: C stress harness uses an explicit C-thunk bridge. P1-5
 * separately exercises the real emitted fastcc bridge. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static _Atomic uint64_t executed;
static _Atomic uint64_t worker_bits;
static myl_block *number(int64_t value) {
    myl_block *block = myl_core_box_new(8);
    *(int64_t *)block_data(block) = value;
    return block;
}
static int64_t read_number(myl_block *block) { return *(int64_t *)block_data(block); }
static myl_block *increment(myl_block *env) {
    atomic_fetch_add_explicit(&executed, 1, memory_order_relaxed);
    if (core_worker) atomic_fetch_or_explicit(&worker_bits, UINT64_C(1) << (core_worker->index % 64), memory_order_relaxed);
    return number(read_number(env) + 1);
}
static void simple(uint64_t count) {
    myl_block *group = myl_core_group_open();
    for (uint64_t i = 0; i < count; ++i) {
        myl_block *task = myl_core_task_submit(group, increment, number(41), (int64_t)i);
        if (i % 127 == 0) {
            myl_block *result = myl_core_task_result(task);
            assert(read_number(result) == 42);
            myl_core_drop_owned(result);
        }
    }
    myl_core_group_close(group);
    myl_core_group_close(group);
    myl_core_drop_owned(group);
}
static myl_block *nested(myl_block *env) {
    int64_t depth = read_number(env);
    if (!depth) return number(1);
    myl_block *group = myl_core_group_open();
    myl_block *left = myl_core_task_submit(group, nested, number(depth - 1), -1);
    myl_block *right = myl_core_task_submit(group, nested, number(depth - 1), -1);
    /* Wait for the older task while our own deque still holds the newer one. */
    myl_block *a = myl_core_task_result(left), *b = myl_core_task_result(right);
    myl_block *answer = number(read_number(a) + read_number(b));
    myl_core_drop_owned(a); myl_core_drop_owned(b);
    /* Deliberately drop without explicit close: finalization must join. */
    myl_core_drop_owned(group);
    return answer;
}
static myl_block *chain(myl_block *env) {
    int64_t depth = read_number(env);
    if (!depth) return number(0);
    myl_block *group = myl_core_group_open(), *child = number(depth - 1);
    myl_block *task = myl_core_task_submit(group, chain, child, -1);
    myl_block *value = myl_core_task_result(task);
    myl_block *result = number(read_number(value) + 1);
    myl_core_drop_owned(value); myl_core_drop_owned(group);
    return result;
}
static void deep_chain(void) {
    myl_block *group = myl_core_group_open(), *env = number(2048);
    myl_block *task = myl_core_task_submit(group, chain, env, -1);
    myl_block *result = myl_core_task_result(task);
    assert(read_number(result) == 2048);
    myl_core_drop_owned(result); myl_core_drop_owned(group);
}
static void deep(void) {
    myl_block *group = myl_core_group_open(), *env = number(12);
    myl_block *task = myl_core_task_submit(group, nested, env, 19);
    myl_block *result = myl_core_task_result(task);
    assert(read_number(result) == 4096);
    myl_core_drop_owned(result); myl_core_drop_owned(group);
}
static void dropped(void) {
    myl_block *group = myl_core_group_open();
    for (int i = 0; i < 10000; ++i)
        (void)myl_core_task_submit(group, increment, number(99), -1);
    myl_core_drop_owned(group);
}
/* P1F-4 (review A6): a waiter has no own work, but another deque holds an unrelated
 * task. The waiter must park until its result is published, rather than run that work.
 * The helper also wakes the pool epoch, so the old scheduler's failure reproduces. */
static myl_block *unexpected_help(myl_block *env) {
    (void)env;
    assert(!"result waiter stole an unrelated task");
    return NULL;
}
static void *finish_own_wait(void *argument) {
    core_task *wanted = argument;
    struct timespec delay = {0, 50000000};
    nanosleep(&delay, NULL);
    wanted->result = number(37);
    atomic_fetch_or_explicit(&wanted->state, 1, memory_order_release);
    syscall(SYS_futex, &wanted->state, FUTEX_WAKE_PRIVATE, INT32_MAX, NULL, NULL, 0);
    atomic_fetch_add_explicit(&core_tasks.epoch, 1, memory_order_release);
    syscall(SYS_futex, &core_tasks.epoch, FUTEX_WAKE_PRIVATE, INT32_MAX, NULL, NULL, 0);
    return NULL;
}
static void own_wait(void) {
    core_task_worker workers[2] = {0};
    for (unsigned i = 0; i < 2; ++i) {
        workers[i].index = i;
        workers[i].victim = 1 - i;
        atomic_init(&workers[i].queue.ring, core_task_ring_new(64, NULL));
    }
    core_tasks.workers = workers;
    core_tasks.size = 2;
    core_worker = &workers[0];
    myl_block *handle = block_new(MYL_KIND_TASK, sizeof(core_task), 1);
    handle->reserved = (int64_t)(intptr_t)core_task_layout;
    core_task *wanted = (core_task *)block_data(handle);
    memset(wanted, 0, sizeof *wanted);
    atomic_init(&wanted->state, 0);
    core_task unrelated = {.run = unexpected_help};
    core_task_push(&workers[1].queue, &unrelated);
    pthread_t helper;
    assert(!pthread_create(&helper, NULL, finish_own_wait, wanted));
    myl_block *result = myl_core_task_result(handle);
    assert(read_number(result) == 37);
    assert(!pthread_join(helper, NULL));
    myl_core_drop_owned(result);
    myl_core_drop_owned(handle);
    assert(core_task_pop(&workers[1].queue) == &unrelated);
    for (unsigned i = 0; i < 2; ++i) free(atomic_load(&workers[i].queue.ring));
    puts("own wait: foreign deque untouched");
}
/* P1F-5: every result is awaited while its task may still sleep, so each waiter parks on
 * its own task and each completion or push must wake the right sleeper, or a wait never ends. */
static myl_block *sleepy(myl_block *env) {
    struct timespec delay = {0, 200000};
    nanosleep(&delay, NULL);
    return number(read_number(env) + 1);
}
static void targeted_waits(void) {
    myl_block *group = myl_core_group_open();
    myl_block *tasks[200];
    for (int64_t i = 0; i < 200; ++i) tasks[i] = myl_core_task_submit(group, sleepy, number(i), i);
    for (int64_t i = 0; i < 200; ++i) {
        myl_block *result = myl_core_task_result(tasks[i]);
        assert(read_number(result) == i + 1);
        myl_core_drop_owned(result);
    }
    myl_core_group_close(group);
    myl_core_drop_owned(group);
    core_tasks_quiesce();
    printf("targeted waits: 200 results, live %lld\n", (long long)live_count());
}
/* P1F-7 (B2): a forged group handle in a task's environment. A worker that submits into the
 * parent's group must trap R_TASK_ESCAPE; the parent sleeps so that a worker, not the parent,
 * takes the task from its deque. */
static myl_block *forged_submit(myl_block *env) {
    myl_block *group = *(myl_block **)block_data(env);
    (void)myl_core_task_submit(group, increment, number(1), -1);
    return NULL;
}
static void escape(void) {
    myl_block *group = myl_core_group_open();
    myl_block *env = myl_core_box_new(sizeof(myl_block *));
    memcpy(block_data(env), &group, sizeof group);
    (void)myl_core_task_submit(group, forged_submit, env, -1);
    struct timespec delay = {0, 50000000};
    nanosleep(&delay, NULL);
    myl_core_group_close(group);
    myl_core_drop_owned(group);
    puts("escape: no trap");
}
int main(int argc, char **argv) {
    alarm(180);
    myl_core_start();
    assert(!core_parallel());
    if (argc > 1 && !strcmp(argv[1], "lazy")) {
        assert(myl_core_threads() >= 1 && !core_parallel());
        myl_block *group = myl_core_group_open(); myl_core_group_close(group); myl_core_drop_owned(group);
        assert(!core_parallel() && live_count() == 0);
        puts("lazy: no workers"); return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "batch")) {
        core_test_batch_parent = true;
        myl_block *group = myl_core_group_open(), *env = number(0);
        (void)myl_core_task_submit(group, increment, env, -1);
        return 90;
    }
    if (argc > 1 && (!strcmp(argv[1], "budget") || !strcmp(argv[1], "frames"))) {
        if (!strcmp(argv[1], "budget")) core_test_bounded = true;
        else core_test_frame_limit = 100;
        assert(myl_core_threads() == 1);
        simple(10); assert(!core_parallel());
        puts("budget: sequential"); return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "escape")) {
        escape();
        return myl_core_exit(0);
    }
    if (argc > 1 && !strcmp(argv[1], "targeted")) {
        targeted_waits();
        return myl_core_exit(0);
    }
    if (argc > 1 && !strcmp(argv[1], "ownwait")) {
        own_wait();
        return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "recursion")) {
        deep_chain();
        core_tasks_quiesce();
        assert(live_count() == 0);
        printf("recursion: completed, live %lld\n", (long long)live_count());
        return myl_core_exit(0);
    }
    if (argc > 1 && !strcmp(argv[1], "reserve")) {
        /* P1F-2: the pool starts under a 64 MiB managed-heap ceiling, or traps R_THREAD_START. */
        myl_core_test_ceilings(0, UINT64_C(64) << 20);
        simple(2000);
        printf("reserve: threads %lld live %lld\n", (long long)myl_core_threads(), (long long)live_count());
        return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "fork")) {
        simple(10);
        assert(core_parallel());
        (void)myl_core_test_run();
        return 90;
    }
    /* `stress` submits a million tasks, `stress-tsan` (the gate's ThreadSanitizer run) 100,000. */
    uint64_t count = argc > 1 && !strcmp(argv[1], "stress") ? 1000000 : argc > 1 && !strcmp(argv[1], "stress-tsan") ? 100000 : 10000;
    int64_t threads = myl_core_threads();
    assert(myl_core_map_chunks(0) == 0);
    assert(myl_core_map_chunks(1) == 1);
    assert(myl_core_map_chunks(1000) == (threads == 1 ? 1 : threads * 4));
    /* Exercise every submission without retaining a million
     * completed results at once under TSan's allocation metadata. Each batch
     * still grows its deque/list, moves environments, and joins every task. */
    for (uint64_t submitted = 0; submitted < count; submitted += 10000)
        simple(count - submitted < 10000 ? count - submitted : 10000);
    deep(); deep_chain(); dropped(); core_tasks_quiesce();
    assert(atomic_load_explicit(&executed, memory_order_relaxed) == count + 10000);
    assert(live_count() == 0);
    assert(core_parallel() == (threads > 1));
    if (threads > 1) assert(atomic_load_explicit(&worker_bits, memory_order_relaxed) & ~UINT64_C(1));
    printf("tasks: %llu submits, binary depth 12, chain 2048, threads %lld, live 0\n", (unsigned long long)(count + 10000), (long long)threads);
    return myl_core_exit(0);
}
