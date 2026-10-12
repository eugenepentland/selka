/* NEW-CORE-ZERO-RC-TASKS-1: count-free scheduler stress and take-once cleanup. */
#define MYL_ZERO_RC 1
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
        myl_core_owned_task_submit(group, increment, number(41), (int64_t)i);
        if (i % 127 == 0) {
            myl_block *value = myl_core_owned_group_take(group, (int64_t)i);
            assert(read_number(value) == 42);
            myl_core_drop_owned(value);
        }
    }
    myl_core_owned_group_end(group);
}
static myl_block *nested(myl_block *env) {
    int64_t depth = read_number(env);
    if (!depth) return number(1);
    myl_block *group = myl_core_group_open();
    myl_core_owned_task_submit(group, nested, number(depth - 1), -1);
    myl_core_owned_task_submit(group, nested, number(depth - 1), -1);
    /* Waiting for the older task must also service our newer queued work. */
    myl_block *a = myl_core_owned_group_take(group, 0), *b = myl_core_owned_group_take(group, 1);
    myl_block *answer = number(read_number(a) + read_number(b));
    myl_core_drop_owned(a); myl_core_drop_owned(b);
    myl_core_drop_owned(group); /* Implicit group destruction still joins. */
    return answer;
}
static myl_block *chain(myl_block *env) {
    int64_t depth = read_number(env);
    if (!depth) return number(0);
    myl_block *group = myl_core_group_open();
    myl_core_owned_task_submit(group, chain, number(depth - 1), -1);
    myl_block *value = myl_core_owned_group_take(group, 0);
    myl_block *result = number(read_number(value) + 1);
    myl_core_drop_owned(value); myl_core_owned_group_end(group);
    return result;
}
static void deep(void) {
    myl_block *group = myl_core_group_open();
    myl_core_owned_task_submit(group, nested, number(12), 19);
    myl_core_owned_task_submit(group, chain, number(2048), 20);
    myl_block *tree = myl_core_owned_group_take(group, 0), *line = myl_core_owned_group_take(group, 1);
    assert(read_number(tree) == 4096 && read_number(line) == 2048);
    myl_core_drop_owned(tree); myl_core_drop_owned(line);
    myl_core_owned_group_end(group);
}
static void take_and_drop(bool twice) {
    myl_block *group = myl_core_group_open();
    myl_core_owned_task_submit(group, increment, number(6), 0);
    myl_core_owned_task_submit(group, increment, number(7), 1);
    myl_block *value = myl_core_owned_group_take(group, 0);
    if (twice) {
        myl_core_drop_owned(value);
        (void)myl_core_owned_group_take(group, 0); /* A second transfer must refuse. */
        abort();
    }
    myl_core_drop_owned(group); /* Joins and drops the other, untaken result. */
    assert(read_number(value) == 7); /* The transferred result is independent. */
    myl_core_drop_owned(value);
}
static void dropped(void) {
    myl_block *group = myl_core_group_open();
    for (int i = 0; i < 10000; ++i)
        myl_core_owned_task_submit(group, increment, number(99), i);
    myl_core_drop_owned(group);
}
int main(int argc, char **argv) {
    alarm(180);
    myl_core_start();
    assert(!core_parallel());
    if (argc > 1 && !strcmp(argv[1], "twice")) { take_and_drop(true); return 90; }
    if (argc > 1 && !strcmp(argv[1], "lazy")) {
        myl_core_owned_group_end(myl_core_group_open());
        assert(!core_parallel() && live_count() == 0);
        puts("lazy: no workers"); return myl_core_exit(0);
    }
    uint64_t count = 1000000;
    int64_t threads = myl_core_threads();
    for (uint64_t submitted = 0; submitted < count; submitted += 10000) simple(10000);
    deep(); dropped(); take_and_drop(false); core_tasks_quiesce();
    assert(atomic_load_explicit(&executed, memory_order_relaxed) == count + 10002);
    assert(live_count() == 0);
    assert(core_parallel() == (threads > 1));
    if (threads > 1) assert(atomic_load_explicit(&worker_bits, memory_order_relaxed) & ~UINT64_C(1));
    printf("owned tasks: %llu submits, binary depth 12, chain 2048, threads %lld, live 0\n", (unsigned long long)(count + 10002), (long long)threads);
    return myl_core_exit(0);
}
