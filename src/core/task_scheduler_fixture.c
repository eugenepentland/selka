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
    myl_block *env = number(41);
    for (uint64_t i = 0; i < count; ++i) {
        myl_block *task = myl_core_task_submit(group, increment, env, (int64_t)i);
        if (i % 127 == 0) {
            myl_block *a = myl_core_task_result(task), *b = myl_core_task_result(task);
            assert(a == b && read_number(a) == 42);
            myl_core_release(a); myl_core_release(b);
        }
        myl_core_release(task);
    }
    myl_core_release(env); /* task-owned environments must survive */
    myl_core_group_close(group);
    myl_core_group_close(group);
    myl_core_release(group);
}
static myl_block *nested(myl_block *env) {
    int64_t depth = read_number(env);
    if (!depth) return number(1);
    myl_block *group = myl_core_group_open();
    myl_block *child = number(depth - 1);
    myl_block *left = myl_core_task_submit(group, nested, child, -1);
    myl_block *right = myl_core_task_submit(group, nested, child, -1);
    myl_core_release(child);
    /* Wait for the older task while our own deque still holds the newer one. */
    myl_block *a = myl_core_task_result(left), *b = myl_core_task_result(right);
    myl_block *answer = number(read_number(a) + read_number(b));
    myl_core_release(a); myl_core_release(b);
    myl_core_release(left); myl_core_release(right);
    /* Deliberately drop without explicit close: finalization must join. */
    myl_core_release(group);
    return answer;
}
static myl_block *chain(myl_block *env) {
    int64_t depth = read_number(env);
    if (!depth) return number(0);
    myl_block *group = myl_core_group_open(), *child = number(depth - 1);
    myl_block *task = myl_core_task_submit(group, chain, child, -1);
    myl_core_release(child);
    myl_block *value = myl_core_task_result(task);
    myl_block *result = number(read_number(value) + 1);
    myl_core_release(value); myl_core_release(task); myl_core_release(group);
    return result;
}
static void deep_chain(void) {
    myl_block *group = myl_core_group_open(), *env = number(2048);
    myl_block *task = myl_core_task_submit(group, chain, env, -1);
    myl_core_release(env);
    myl_block *result = myl_core_task_result(task);
    assert(read_number(result) == 2048);
    myl_core_release(result); myl_core_release(task); myl_core_release(group);
}
static void deep(void) {
    myl_block *group = myl_core_group_open(), *env = number(12);
    myl_block *task = myl_core_task_submit(group, nested, env, 19);
    myl_core_release(env);
    myl_block *result = myl_core_task_result(task);
    assert(read_number(result) == 4096);
    myl_core_release(result); myl_core_release(task); myl_core_release(group);
}
typedef struct { myl_block *expected; unsigned seen; } one_child;
static void observe_one(myl_block *child, void *context) {
    one_child *found = context;
    assert(child == found->expected);
    ++found->seen;
}
static myl_block *identity(myl_block *env) { return number(read_number(env)); }
static void post_close(void) {
    myl_block *group = myl_core_group_open(), *env = number(7);
    myl_block *task = myl_core_task_submit(group, identity, env, -1);
    if (myl_core_threads() == 1) assert(count_load(env) == 1);
    myl_core_release(env);
    myl_block *before = myl_core_task_result(task);
    one_child result = {before, 0};
    core_children(task, observe_one, &result);
    assert(result.seen == 1);
    one_child handles = {((core_group *)block_data(group))->tasks, 0};
    core_children(group, observe_one, &handles);
    assert(handles.seen == 1);
    myl_core_release(before);
    myl_core_group_close(group);
    one_child closed = {NULL, 0};
    core_children(group, observe_one, &closed);
    assert(closed.seen == 0);
    myl_core_release(group); /* the handle must no longer need this pointer */
    myl_block *a = myl_core_task_result(task), *b = myl_core_task_result(task);
    assert(a == b && read_number(a) == 7);
    myl_core_release(a); myl_core_release(b); myl_core_release(task);
}
static void dropped(void) {
    myl_block *group = myl_core_group_open(), *env = number(99);
    for (int i = 0; i < 10000; ++i) {
        myl_block *task = myl_core_task_submit(group, increment, env, -1);
        myl_core_release(task);
    }
    myl_core_release(env);
    myl_core_release(group);
}
int main(int argc, char **argv) {
    alarm(180);
    myl_core_start();
    assert(!core_parallel());
    if (argc > 1 && !strcmp(argv[1], "lazy")) {
        assert(myl_core_threads() >= 1 && !core_parallel());
        myl_block *group = myl_core_group_open(); myl_core_group_close(group); myl_core_release(group);
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
    if (argc > 1 && !strcmp(argv[1], "fork")) {
        simple(10);
        assert(core_parallel());
        (void)myl_core_test_run();
        return 90;
    }
    uint64_t count = argc > 1 && !strcmp(argv[1], "stress") ? 1000000 : 10000;
    int64_t threads = myl_core_threads();
    assert(myl_core_map_chunks(0) == 0);
    assert(myl_core_map_chunks(1) == 1);
    assert(myl_core_map_chunks(1000) == (threads == 1 ? 1 : threads * 4));
    /* Exercise all one million submissions without retaining one million
     * completed results at once under TSan's allocation metadata. Each batch
     * still grows its deque/list, shares environments, and joins every task. */
    for (uint64_t submitted = 0; submitted < count; submitted += 10000)
        simple(count - submitted < 10000 ? count - submitted : 10000);
    deep(); deep_chain(); dropped(); post_close(); core_tasks_quiesce();
    assert(atomic_load_explicit(&executed, memory_order_relaxed) == count + 10000);
    assert(live_count() == 0);
    assert(core_parallel() == (threads > 1));
    if (threads > 1) assert(atomic_load_explicit(&worker_bits, memory_order_relaxed) & ~UINT64_C(1));
    printf("tasks: %llu submits, binary depth 12, chain 2048, threads %lld, live 0\n", (unsigned long long)(count + 10000), (long long)threads);
    return myl_core_exit(0);
}
