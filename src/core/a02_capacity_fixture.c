/* OWNED-CAPACITY-BOUNDS-1: native allocation boundary regression. */
#include "core_rt.c"

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    switch (atoi(argv[1])) {
    case 0: {
        myl_block *list = myl_core_list_new_slow(0, 8);
        for (int64_t i = 0; i < 4096; ++i) {
            list = myl_core_list_grow(list, 8);
            ((int64_t *)block_data(list))[list->len++] = i;
        }
        for (int64_t i = 0; i < 4096; ++i) {
            if (((int64_t *)block_data(list))[i] != i) return 3;
        }
        block_free(list);
        myl_block *units = myl_core_list_new_slow(9, 0);
        if (units->cap != 9) return 4;
        block_free(units);
        myl_block *buffer = myl_core_buffer_new(0);
        for (int i = 0; i < 4096; ++i) buffer = myl_core_buffer_push(buffer, (uint8_t)i);
        myl_block *snapshot = myl_core_buffer_snapshot(buffer);
        buffer = myl_core_buffer_push(buffer, 42);
        if (snapshot->len != 4096 || block_data(snapshot)[4095] != 255) return 5;
        if (myl_core_buffer_reserve_valid(buffer, -1)) return 6;
        if (myl_core_buffer_reserve_valid(buffer, INT64_MAX)) return 7;
        if (!myl_core_buffer_reserve_valid(buffer, INT64_MAX - buffer->len)) return 8;
        block_free(snapshot);
        block_free(buffer);
        if (live_count()) return 9;
        puts("preserved");
        return 0;
    }
    case 1: (void)myl_core_list_new_slow(-1, 8); break;
    case 2: (void)myl_core_list_new_slow(1, -1); break;
    case 3: (void)myl_core_list_new_slow(INT64_C(2305843009213693952), 8); break;
    case 4: {
        size_t room;
        (void)block_alloc(MYL_KIND_LIST, SIZE_MAX - 31, &room);
        break;
    }
    case 5: {
        size_t room;
        (void)block_alloc(MYL_KIND_LIST, SIZE_MAX - MYL_HEADER - 15, &room);
        break;
    }
    case 6: {
        myl_block *list = myl_core_list_new_slow(0, 8);
        list->cap = list->len = INT64_MAX;
        (void)myl_core_list_grow(list, 8);
        break;
    }
    case 7: (void)myl_core_buffer_new(UINT64_MAX); break;
    case 8: {
        myl_block *list = myl_core_list_new_slow(128, 8);
        list->cap = list->len = INT64_C(1152921504606846976);
        (void)myl_core_list_grow(list, 8);
        break;
    }
    case 9:
        heap_ceiling = 1;
        (void)myl_core_buffer_new(1000000);
        break;
    case 10:
        (void)block_new(MYL_KIND_STR, INT64_MAX, 2);
        break;
    default: return 10;
    }
    puts("incorrectly admitted");
    return 11;
}
