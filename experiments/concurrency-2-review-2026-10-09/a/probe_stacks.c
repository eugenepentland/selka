#include "core_rt_all.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *nothing(myl_block *env) { (void)env; return NULL; }
int main(int argc, char **argv) {
    myl_core_start();
    myl_core_test_ceilings(0, (uint64_t)atoll(argv[1]) << 20);   /* mylang run --max-memory: RLIMIT_AS = M + 256 MiB */
    myl_block *group = myl_core_group_open();
    myl_block *t = myl_core_task_submit(group, nothing, NULL, -1);
    myl_core_release(t); myl_core_group_close(group); myl_core_release(group);
    puts("pool started");
    return myl_core_exit(0);
}
