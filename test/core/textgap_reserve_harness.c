#include "core_rt.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "capacity-harness";
static int check_split(const unsigned char *text, uint64_t len, const unsigned char *separator, uint64_t width) {
    myl_block *list = myl_core_span_split_offsets(text, len, separator, width);
    const uint64_t *pairs = (const uint64_t *)block_data(list);
    uint64_t start = 0, index = 0;
    for (;;) {
        uint64_t end = start;
        while (end + width <= len && memcmp(text + end, separator, (size_t)width)) ++end;
        const int found = end + width <= len;
        if (!found) end = len;
        if (index >= (uint64_t)list->len || pairs[2*index] != start || pairs[2*index+1] != end-start) return 4;
        ++index;
        if (!found) break;
        start = end + width;
    }
    if (index != (uint64_t)list->len) return 5;
    myl_core_release(list);
    return 0;
}
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
    const struct { const unsigned char *text, *separator; uint64_t length, width; } cases[] = {
        {(const unsigned char *)"", (const unsigned char *)"::", 0, 2},
        {(const unsigned char *)":", (const unsigned char *)"::", 1, 2},
        {(const unsigned char *)"::", (const unsigned char *)"::", 2, 2},
        {(const unsigned char *)"::::x::", (const unsigned char *)"::", 7, 2},
        {(const unsigned char *)"aaaaaaaaaaaaaaaaaab", (const unsigned char *)"ab", 19, 2},
        {(const unsigned char *)"aaaaaaaaaaaaaaaaaaa", (const unsigned char *)"ab", 19, 2},
        {(const unsigned char *)"x\xc3\xa9\xc3\xa9z\xc3\xa9", (const unsigned char *)"\xc3\xa9", 8, 2},
        {(const unsigned char *)"a\0za\0z", (const unsigned char *)"\0z", 6, 2},
        {(const unsigned char *)"abababa", (const unsigned char *)"aba", 7, 3},
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        int status = check_split(cases[i].text, cases[i].length, cases[i].separator, cases[i].width);
        if (status) return status;
    }
    if (live_count() != 0) return 3;
    return 0;
}
