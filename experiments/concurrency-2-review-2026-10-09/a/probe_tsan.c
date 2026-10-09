#include "core_rt_all.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *text(const char *s) { return str_from(s, strlen(s)); }
static myl_block *work(myl_block *env) {
    /* env: the shared entropy stand-in capability */
    for (int i = 0; i < 50; ++i) {
        myl_block *r = myl_core_external_read(env, 1);
        myl_core_release(r);
        myl_block *s = text("line");
        myl_core_print_str(1, s); myl_core_print_sep(1); myl_core_print_i64(1, i); myl_core_print_end(1);
        myl_core_output_begin(2); myl_core_stream_write(2, s); myl_core_stream_write(2, s); myl_core_output_end(2);
        myl_block *own = myl_core_stand_in(0, i);
        myl_block *c = myl_core_external_read(own, 0); myl_core_release(c); myl_core_release(own);
        myl_core_release(s);
    }
    return text("done");
}
int main(void) {
    myl_core_start();
    myl_block *cap = myl_core_stand_in(1, 7);
    for (int round = 0; round < 20; ++round) {
        myl_block *group = myl_core_group_open(), *tasks[16];
        for (int i = 0; i < 16; ++i) tasks[i] = myl_core_task_submit(group, work, cap, i);
        for (int i = 0; i < 16; ++i) { myl_block *v = myl_core_task_result(tasks[i]); myl_core_release(v); myl_core_release(tasks[i]); }
        myl_core_group_close(group); myl_core_release(group);
    }
    myl_core_release(cap);
    fprintf(stderr, "live %lld\n", (long long)live_count());
    return myl_core_exit(0);
}
