#include "native_collections.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { MAX_RECORDED_SIZE = 512 };
static uint64_t calls[MAX_RECORDED_SIZE + 1];
static uint64_t requested[MAX_RECORDED_SIZE + 1];
static uint64_t overflow_calls;
static uint64_t overflow_requested;
static uint64_t failures;

extern int __real_myl_native_list_get(const myl_native_list *, size_t, void *);

int __wrap_myl_native_list_get(const myl_native_list *list, size_t index, void *output) {
    size_t size = list && list->element ? list->element->size : 0;
    int result = __real_myl_native_list_get(list, index, output);
    if (size <= MAX_RECORDED_SIZE) {
        calls[size] += 1;
        requested[size] += size;
    } else {
        overflow_calls += 1;
        overflow_requested += size;
    }
    if (!result) failures += 1;
    return result;
}

static void report(void) {
    uint64_t total_calls = overflow_calls;
    uint64_t total_requested = overflow_requested;
    for (size_t size = 0; size <= MAX_RECORDED_SIZE; size++) {
        if (calls[size]) {
            fprintf(stderr, "LIST_GET size=%zu calls=%llu requested_bytes=%llu\n",
                    size, (unsigned long long)calls[size],
                    (unsigned long long)requested[size]);
            total_calls += calls[size];
            total_requested += requested[size];
        }
    }
    fprintf(stderr, "LIST_GET_TOTAL calls=%llu requested_bytes=%llu failures=%llu overflow_calls=%llu overflow_requested_bytes=%llu\n",
            (unsigned long long)total_calls, (unsigned long long)total_requested,
            (unsigned long long)failures, (unsigned long long)overflow_calls,
            (unsigned long long)overflow_requested);
}

__attribute__((constructor)) static void install_report(void) {
    if (atexit(report) != 0) abort();
}
