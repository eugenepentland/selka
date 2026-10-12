/* Native runtime policy probe. No source lowering or guest timing claim. */
#include "runtime.c"
myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

static uint64_t checksum, final_length, final_capacity;

static void append_list(myl_block **list, int64_t size, uint64_t value) {
    *list = myl_core_list_grow(*list, size);
    memcpy(block_data(*list) + (*list)->len * size, &value, sizeof value);
    ++(*list)->len;
}

static void nested(int repetitions) {
    for (int r = 0; r < repetitions; ++r) {
        myl_block *nodes[60];
        uint64_t capacity = 0;
        for (int i = 0; i < 60; ++i) {
            nodes[i] = myl_core_list_new_slow(0, 24);
            append_list(&nodes[i], 24, (uint64_t)i);
            capacity += (uint64_t)nodes[i]->cap;
            checksum += *(uint64_t *)block_data(nodes[i]);
        }
        final_length = 60;
        final_capacity = capacity;
        for (int i = 59; i >= 0; --i) block_free(nodes[i]);
    }
}

static void lists(int repetitions, int clear, int replacement) {
    myl_block *list = myl_core_list_new_slow(0, 8);
    int length = replacement ? 3 : 1000000;
    for (int r = 0; r < repetitions; ++r) {
        if (r && !clear) {
            myl_block *next = myl_core_list_new_slow(0, 8);
            block_free(list);
            list = next;
        }
        list->len = 0;
        for (int i = 0; i < length; ++i) append_list(&list, 8, (uint64_t)i);
        checksum += *(uint64_t *)(block_data(list) + (list->len - 1) * 8);
    }
    final_length = (uint64_t)list->len;
    final_capacity = (uint64_t)list->cap;
    block_free(list);
}

static void buffers(int repetitions, int reserved) {
    for (int r = 0; r < repetitions; ++r) {
        myl_block *buffer = myl_core_buffer_new(0);
        if (reserved) {
            myl_block *next = myl_core_buffer_reserved(buffer, 1000000);
            block_free(buffer);
            buffer = next;
        }
        for (int i = 0; i < 1000000; ++i) buffer = myl_core_buffer_push(buffer, (uint8_t)i);
        myl_block *snapshot = myl_core_buffer_snapshot(buffer);
        buffer = myl_core_buffer_push(buffer, 42);
        if (snapshot->len != 1000000 || block_data(snapshot)[999999] != 63) abort();
        checksum += block_data(buffer)[1000000];
        final_length = (uint64_t)buffer->len;
        final_capacity = (uint64_t)buffer->cap;
        block_free(snapshot);
        block_free(buffer);
    }
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    int repetitions = atoi(argv[2]);
    if (!strcmp(argv[1], "nested")) nested(repetitions);
    else if (!strcmp(argv[1], "append")) lists(repetitions, 0, 0);
    else if (!strcmp(argv[1], "reuse")) lists(repetitions, 1, 0);
    else if (!strcmp(argv[1], "replacement")) lists(repetitions, 0, 1);
    else if (!strcmp(argv[1], "buffer")) buffers(repetitions, 0);
    else if (!strcmp(argv[1], "reserved")) buffers(repetitions, 1);
    else if (!strcmp(argv[1], "overflow_product")) {
        myl_block *bad = myl_core_list_new_slow(INT64_C(2305843009213693952), 8);
        final_capacity = (uint64_t)bad->cap;
        block_free(bad);
    } else if (!strcmp(argv[1], "overflow_round")) {
        size_t room;
        myl_block *bad = block_alloc(MYL_KIND_LIST, SIZE_MAX - 31, &room);
        final_capacity = room;
        block_free(bad);
    } else if (!strcmp(argv[1], "overflow_growth")) {
        myl_block *bad = myl_core_list_new_slow(0, 8);
        bad->cap = INT64_MAX;
        bad->len = INT64_MAX;
        bad = myl_core_list_grow(bad, 8);
        block_free(bad);
    } else if (!strcmp(argv[1], "budget")) {
        heap_ceiling = 1;
        (void)myl_core_buffer_new(1000000);
    } else return 3;
    if (live_count()) return 4;
    printf("{\"checksum\":%llu,\"length\":%llu,\"capacity\":%llu}\n",
           (unsigned long long)checksum, (unsigned long long)final_length,
           (unsigned long long)final_capacity);
#ifdef A02_COUNTED
    myl_count_dump();
#endif
    return 0;
}
