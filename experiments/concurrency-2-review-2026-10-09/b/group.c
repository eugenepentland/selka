#include "core_rt_all.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *leafy(myl_block *env) { (void)env; return NULL; }
static myl_block *nested(myl_block *env) {
    /* env is a box holding the group: a task submits into the captured group */
    myl_block *g = *(myl_block **)block_data(env);
    for (int i = 0; i < 200; ++i) { myl_block *h = myl_core_task_submit(g, (void *)leafy, NULL, -1); myl_core_release(h); }
    return NULL;
}
int main(void) {
    myl_block *g = myl_core_group_open();
    myl_block *env = myl_core_box_new(8);
    env->reserved = (int64_t)(intptr_t)layout_blocks;
    *(myl_block **)block_data(env) = g; count_retain(g);
    myl_block *h = myl_core_task_submit(g, (void *)nested, env, -1);
    core_group *group = (core_group *)block_data(g);
    printf("group count %#x tasks-list count %#x\n", count_load(g), count_load(group->tasks));
    for (int i = 0; i < 200; ++i) { myl_block *x = myl_core_task_submit(g, (void *)leafy, NULL, -1); myl_core_release(x); }
    myl_core_release(h);
    myl_core_group_close(g);
    myl_core_release(env);
    myl_core_release(g);
    return myl_core_exit(0);
}
