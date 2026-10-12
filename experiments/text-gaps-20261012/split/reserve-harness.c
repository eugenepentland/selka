#include "core_rt.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "capacity-harness";
int main(void) {
    const uint64_t lengths[] = {0, 1, 126, 127, 128, UINT64_MAX, UINT64_MAX, UINT64_MAX};
    const uint64_t widths[] = {1, 1, 1, 1, 1, 1, 2, UINT64_MAX};
    const uint64_t expected[] = {1, 2, 127, 128, 128, 128, 128, 2};
    for (unsigned i = 0; i < sizeof(lengths)/sizeof(lengths[0]); ++i) {
        if (core_split_initial_capacity(lengths[i], widths[i]) != expected[i]) return 1;
    }
    unsigned char sparse[8192]; memset(sparse, 'a', sizeof sparse);
    myl_block *list = myl_core_span_split_offsets(sparse, sizeof sparse, (const unsigned char *)"|", 1);
    const uint64_t *pair = (const uint64_t *)block_data(list);
    if (list->len != 1 || list->cap > 128 || pair[0] != 0 || pair[1] != sizeof sparse) return 2;
    printf("%lld %lld %llu\n", (long long)list->len, (long long)list->cap, (unsigned long long)pair[1]);
    myl_core_release(list);
    if (live_count() != 0) return 3;
    return 0;
}
