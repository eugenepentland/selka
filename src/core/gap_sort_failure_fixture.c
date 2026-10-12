/* Optional gather scratch failure must preserve the original owned sort path. */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#include <stdlib.h>
#include <stddef.h>
static size_t sort_scratch_size;
static unsigned sort_scratch_calls;
static int refuse_sort_scratch;
static void *sort_test_malloc(size_t size) {
    if (sort_scratch_size && size == sort_scratch_size) {
        sort_scratch_calls++;
        if (refuse_sort_scratch) return NULL;
    }
    return malloc(size);
}
#define malloc sort_test_malloc
#undef _POSIX_C_SOURCE
#undef _XOPEN_SOURCE
#include "core_rt.c"
#undef malloc

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

typedef struct { int64_t rank, ordinal; myl_block *child; } sort_row;
static const int32_t sort_row_layout[] = { sizeof(sort_row), 1, 0, offsetof(sort_row, child), 0 };

int main(void) {
    const size_t count = 97;
    for (int fail = 0; fail < 2; fail++) for (int reverse = 0; reverse < 2; reverse++) {
        sort_scratch_size = 0;
        myl_block *values = myl_core_list_new_slow((int64_t)count, sizeof(sort_row));
        myl_block *keys = myl_core_list_new_slow((int64_t)count, sizeof(int64_t));
        values->reserved = (int64_t)(intptr_t)sort_row_layout;
        sort_row *rows = (sort_row *)block_data(values);
        for (size_t i = 0; i < count; i++) {
            myl_block *child = block_new(MYL_KIND_BYTES, sizeof(int64_t), 1);
            int64_t ordinal = (int64_t)i;
            memcpy(block_data(child), &ordinal, sizeof ordinal);
            rows[i] = (sort_row){ (int64_t)((i * 13) % 7), ordinal, child };
            ((int64_t *)block_data(keys))[i] = rows[i].rank;
        }
        values->len = keys->len = (int64_t)count;
        int64_t capacity = values->cap;
        sort_scratch_size = count * sizeof(sort_row);
        sort_scratch_calls = 0;
        refuse_sort_scratch = fail;
        myl_block *result = myl_core_owned_sort_keyed(values, keys, 1, 0, reverse,
            ((uint64_t)sizeof(int64_t) << 32) | sizeof(sort_row));
        sort_scratch_size = 0;
        if (result != values || result->cap != capacity || result->len != (int64_t)count || sort_scratch_calls != 1) return 2;
        for (size_t i = 0; i < count; i++) {
            int64_t child;
            memcpy(&child, block_data(rows[i].child), sizeof child);
            if (child != rows[i].ordinal) return 3;
            if (i && (rows[i - 1].rank == rows[i].rank ? rows[i - 1].ordinal > rows[i].ordinal :
                reverse ? rows[i - 1].rank < rows[i].rank : rows[i - 1].rank > rows[i].rank)) return 4;
        }
        myl_core_drop_owned(values);
        if (live_count()) return 5;
    }
    /* An impossible byte product must fail before scanning invalid metadata. */
    pid_t child = fork();
    if (child < 0) return 6;
    if (child == 0) {
        myl_block *values = myl_core_list_new_slow(1, sizeof(sort_row));
        myl_block *keys = myl_core_list_new_slow(1, sizeof(int64_t));
        values->len = keys->len = INT64_MAX;
        (void)myl_core_owned_sort_keyed(values, keys, 1, 0, false,
            ((uint64_t)sizeof(int64_t) << 32) | sizeof(sort_row));
        _Exit(99);
    }
    int status;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 1) return 7;
    puts("scratch success and failure preserve stable managed ownership");
    return 0;
}
