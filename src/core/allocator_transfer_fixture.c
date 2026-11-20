/* RUNTIME-THREADS-2 (P1F-1): repeated cross-thread frees reuse bounded storage.
 * Each round submits 64 tasks; every worker frees the environment it was given and
 * the parent frees the result it took, so every block crosses threads once. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>

myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }

static myl_block *produce(myl_block *env) {
    int64_t bytes = *(int64_t *)block_data(env);
    myl_block *block = myl_core_box_new(bytes);
    if (bytes) memset(block_data(block), 0x5a, (size_t)bytes);
    return block;
}

static void transfer(unsigned rounds, bool varied) {
    for (unsigned round = 0; round < rounds; ++round) {
        myl_block *group = myl_core_group_open(), *tasks[64];
        for (unsigned item = 0; item < 64; ++item) {
            myl_block *env = myl_core_box_new(8);
            /* The environment is a 8-byte box; each result is `bytes` long. Growth: results
               are a larger class than environments, so a parent that frees results never
               takes back the blocks its workers carved. Varied: every small size class. */
            *(int64_t *)block_data(env) = varied ? (int64_t)((round + item) % MYL_CLASSES) * MYL_GRANULE : 200;
            tasks[item] = myl_core_task_submit(group, produce, env, (int64_t)item);
        }
        for (unsigned item = 0; item < 64; ++item) {
            myl_block *result = myl_core_task_result(tasks[item]);
            myl_core_drop_owned(result);
        }
        myl_core_group_close(group);
        myl_core_drop_owned(group);
        core_tasks_quiesce();
        assert(live_count() == 0);
    }
    printf("allocator transfer: %s rounds=%u carved=%lld live=0\n", varied ? "varied" : "growth", rounds,
        (long long)atomic_load_explicit(&live_blocks, memory_order_relaxed));
}

int main(int argc, char **argv) {
    alarm(120);
    myl_core_start();
    bool varied = argc > 1 && strstr(argv[1], "varied");
    bool sanitized = argc > 1 && strstr(argv[1], "sanitized");
    /* TSan reserves its address space itself; keep the same allocator ceiling
       without lowering RLIMIT_AS over that sanitizer reservation. */
    if (sanitized) heap_ceiling = UINT64_C(64) << 20;
    else myl_core_test_ceilings(0, UINT64_C(64) << 20);
    /* Growth runs 10,000 rounds, or 40,000 in the full stress mode (`growth-full`). */
    bool full = argc > 1 && strstr(argv[1], "full");
    transfer(varied ? 1024 : sanitized ? 4000 : full ? 40000 : 10000, varied);
    return myl_core_exit(0);
}
