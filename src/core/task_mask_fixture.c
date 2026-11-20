/* E1 drop mask: a task environment with lent and owned references (core_tasks.c, myl_core_owned_task_submit_masked).
 * A lent reference is borrowed and must survive the task and the join; an owned one is released by the environment
 * unless the thunk takes it. Every mode ends with no live block: a leak or a double release fails the run. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }

/* A two-reference environment: size 16, reference 0 at offset 0 and reference 1 at offset 8, both unguarded. */
static const int32_t pair_layout[] = {16, 2, 0, 0, 0, 8, 0};

/* A 4 KiB value, so every release reaches the large-block path (a double release is then a glibc fault, not a silent
   free-list corruption). */
static myl_block *number(int64_t value) {
    myl_block *block = myl_core_box_new(4096);
    *(int64_t *)block_data(block) = value;
    return block;
}
static int64_t read_number(myl_block *block) { return *(int64_t *)block_data(block); }
static myl_block *pair_env(myl_block *first, myl_block *second) {
    myl_block *env = myl_core_box_new(16);
    env->reserved = (int64_t)(intptr_t)pair_layout;
    memcpy(block_data(env), &first, sizeof first);
    memcpy(block_data(env) + 8, &second, sizeof second);
    return env;
}
static myl_block *first_reference(myl_block *env) { myl_block *value; memcpy(&value, block_data(env), sizeof value); return value; }
static myl_block *second_reference(myl_block *env) { myl_block *value; memcpy(&value, block_data(env) + 8, sizeof value); return value; }

/* Reads both references and leaves them in the environment. */
static myl_block *sum_both(myl_block *env) {
    return number(read_number(first_reference(env)) + read_number(second_reference(env)));
}
/* Takes the first reference out of the environment (it clears the slot), releases it, reads the second. */
static myl_block *take_first(myl_block *env) {
    myl_block *first = first_reference(env), *none = NULL;
    memcpy(block_data(env), &none, sizeof none);
    int64_t value = read_number(first) + read_number(second_reference(env));
    myl_core_drop_owned(first);
    return number(value);
}

/* Runs one submitted task with `own` and returns its sum; the caller checks what the environment released. */
static int64_t submit_and_join(myl_block *env, myl_block *(*run)(myl_block *), uint64_t own) {
    myl_block *group = myl_core_group_open();
    myl_block *task = myl_core_owned_task_submit_masked(group, run, env, -1, own);
    myl_block *result = myl_core_task_result(task);
    int64_t value = read_number(result);
    myl_core_drop_owned(result);
    myl_core_group_close(group);
    myl_core_drop_owned(group);
    return value;
}

static void lent_only(void) {
    myl_block *a = number(1), *b = number(2);
    assert(submit_and_join(pair_env(a, b), sum_both, 0) == 3);
    /* Lent: the environment did not release them, so the caller still reads and releases both. */
    assert(read_number(a) == 1 && read_number(b) == 2);
    myl_core_drop_owned(a);
    myl_core_drop_owned(b);
    assert(live_count() == 0);
}
static void owned_only(void) {
    myl_block *a = number(10), *b = number(20);
    assert(submit_and_join(pair_env(a, b), sum_both, UINT64_MAX) == 30);
    /* Owned and not taken: the environment released both at the task's end, so the caller holds nothing. */
    assert(live_count() == 0);
}
static void mixed(void) {
    myl_block *own = number(5), *lent = number(6);
    /* Bit 0 owns reference 0; reference 1 is lent. */
    assert(submit_and_join(pair_env(own, lent), sum_both, 1) == 11);
    assert(read_number(lent) == 6);
    myl_core_drop_owned(lent);
    assert(live_count() == 0);
}
static void taken(void) {
    myl_block *a = number(7), *b = number(8);
    assert(submit_and_join(pair_env(a, b), take_first, UINT64_MAX) == 15);
    /* The thunk took and released the first reference; the environment released the second. */
    assert(live_count() == 0);
}

int main(int argc, char **argv) {
    alarm(120);
    myl_core_start();
    assert(argc > 1);
    if (!strcmp(argv[1], "lent")) lent_only();
    else if (!strcmp(argv[1], "owned")) owned_only();
    else if (!strcmp(argv[1], "mixed")) mixed();
    else if (!strcmp(argv[1], "taken")) taken();
    else return 2;
    puts("mask: ok");
    return 0;
}
