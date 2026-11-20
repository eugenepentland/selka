/* ASAN-TASK-START-1: real workers consume independently owned 32 KiB inputs. */
#ifdef TASK_REFUSE_MALLOPT
#define mallopt task_refused_mallopt
#endif
#include "core_rt_all.c"
#ifdef TASK_REFUSE_MALLOPT
#undef mallopt
int task_refused_mallopt(int parameter, int value) { (void)value; return parameter == M_ARENA_MAX ? 0 : 1; }
#endif
#undef NDEBUG
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static _Atomic uint32_t entered, release_workers;
static _Atomic uint64_t worker_mask;
enum { INPUT_ITEMS = 4096 };
static myl_block *sum_input(myl_block *env) {
    assert(core_worker && core_worker->index > 0);
    atomic_fetch_or_explicit(&worker_mask, UINT64_C(1) << core_worker->index, memory_order_relaxed);
    atomic_fetch_add_explicit(&entered, 1, memory_order_release);
    while (!atomic_load_explicit(&release_workers, memory_order_acquire)) sched_yield();
    int64_t total = 0;
    for (int i = 0; i < INPUT_ITEMS; ++i) total += ((int64_t *)block_data(env))[i];
    myl_block *result = myl_core_box_new(sizeof total);
    memcpy(block_data(result), &total, sizeof total);
    return result;
}
static void workers(void) {
    uint32_t threads = (uint32_t)myl_core_threads();
    assert(threads >= 2 && threads <= 4);
    myl_block *group = myl_core_group_open(), *handles[3];
    for (uint32_t i = 0; i < threads - 1; ++i) {
        myl_block *input = myl_core_box_new(INPUT_ITEMS * sizeof(int64_t));
        for (int item = 0; item < INPUT_ITEMS; ++item) ((int64_t *)block_data(input))[item] = item;
        handles[i] = myl_core_task_submit(group, sum_input, input, i);
    }
    /* The parent never runs a task while waiting: every worker must enter. */
    while (atomic_load_explicit(&entered, memory_order_acquire) != threads - 1) sched_yield();
    uint64_t mask = atomic_load_explicit(&worker_mask, memory_order_relaxed);
    assert(core_tasks.size == threads && mask == ((UINT64_C(1) << threads) - 2));
    atomic_store_explicit(&release_workers, 1, memory_order_release);
    int64_t total = 0;
    for (uint32_t i = 0; i < threads - 1; ++i) {
        myl_block *result = myl_core_task_result(handles[i]);
        total += *(int64_t *)block_data(result);
        myl_core_drop_owned(result);
    }
    myl_core_group_close(group);
    myl_core_drop_owned(group);
    core_tasks_quiesce();
    assert(total == (int64_t)(threads - 1) * INPUT_ITEMS * (INPUT_ITEMS - 1) / 2);
    assert(live_count() == 0);
    printf("threads=%u workers=%u mask=%llu input_bytes=%zu sum=%lld live=0\n",
        threads, threads - 1, (unsigned long long)mask, INPUT_ITEMS * sizeof(int64_t), (long long)total);
    fflush(stdout);
}
int main(int argc, char **argv) {
    alarm(30);
    myl_core_start();
    bool limited = argc > 1 && !strcmp(argv[1], "heap-limit");
    if (limited) myl_core_test_ceilings(0, UINT64_C(64) << 20);
    workers();
    if (limited) {
        assert(heap_ceiling == (UINT64_C(64) << 20));
        (void)myl_core_box_new(UINT64_C(65) << 20);
        return 99;
    }
    return myl_core_exit(0);
}
