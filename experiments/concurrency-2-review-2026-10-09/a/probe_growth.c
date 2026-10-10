#include "core_rt_all.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *number(int64_t v) { myl_block *b = myl_core_box_new(8); *(int64_t *)block_data(b) = v; return b; }
static myl_block *produce(myl_block *env) { return number(*(int64_t *)block_data(env) + 1); }
int main(int argc, char **argv) {
    myl_core_start();
    if (argc > 2) myl_core_test_ceilings(0, (uint64_t)atoll(argv[2]) << 20);
    long rounds = argc > 1 ? atol(argv[1]) : 1000;
    myl_block *env = number(1);
    for (long r = 0; r < rounds; ++r) {
        myl_block *group = myl_core_group_open();
        myl_block *tasks[64];
        for (int i = 0; i < 64; ++i) tasks[i] = myl_core_task_submit(group, produce, env, -1);
        for (int i = 0; i < 64; ++i) { myl_block *v = myl_core_task_result(tasks[i]); myl_core_release(v); myl_core_release(tasks[i]); }
        myl_core_group_close(group); myl_core_release(group);
        if ((r + 1) % (rounds / 4) == 0) {
            core_tasks_quiesce();
            fprintf(stderr, "round %ld: live %lld carved %lld (~%lld KiB of chunks)\n", r + 1, (long long)live_count(),
                (long long)atomic_load(&live_blocks), (long long)atomic_load(&live_blocks) * 64 / 1024);
        }
    }
    myl_core_release(env);
    return myl_core_exit(0);
}
