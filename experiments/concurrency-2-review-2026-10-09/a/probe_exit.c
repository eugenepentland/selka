#include "core_rt_all.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *nothing(myl_block *env) { (void)env; return NULL; }
int main(void) {
    myl_core_start();
    myl_block *group = myl_core_group_open();
    myl_block *t = myl_core_task_submit(group, nothing, NULL, -1);
    myl_core_release(t); myl_core_group_close(group); myl_core_release(group);
    core_io_fail("InvalidCapability");   /* host/provider failure: documented status 2 */
}
